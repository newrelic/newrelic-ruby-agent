# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'

module NewRelic
  module Agent
    # Samples Puma's clustered server statistics from the Puma master process
    # and records them as New Relic timeslice metrics under +Puma/*+.
    #
    # This class is driven by the Puma plugin defined in
    # +lib/puma/plugin/newrelic.rb+ (activated with <tt>plugin 'newrelic'</tt>
    # in +puma.rb+). It is intentionally *not* one of the agent's
    # harvest-driven NewRelic::Agent::Sampler subclasses; see "Why the master
    # process" below.
    #
    # == Why the master process
    #
    # Only the Puma master exposes cluster-wide statistics through
    # +Puma::Launcher#stats+ (per-worker thread-pool backlog, running threads,
    # +pool_capacity+, configured max threads, and cumulative request count).
    # Worker processes have no reliable handle to their own server statistics
    # from a background thread (+Puma.stats_object+ is set only in the master
    # and +Puma::Server.current+ is request-thread-local), so sampling must
    # happen in the master. That rules out a harvest-driven Sampler, whose
    # +poll+ runs only on the per-worker harvest thread.
    #
    # == Why the harvest thread is restarted
    #
    # The agent intentionally defers starting its reporting (harvest) thread
    # under forking dispatchers such as Puma, because the master forks workers
    # that each start their own agent after forking. As a result, metrics
    # recorded from the master are buffered but never sent. To deliver the
    # sampled metrics, this class restarts the harvest thread in the master via
    # the agent's own +NewRelic::Agent.after_fork(force_reconnect: true)+ entry
    # point (the same call the agent's Harvester uses to recover in forked
    # children). The master then reports to New Relic as its own instance. This
    # behavior can be disabled with the +puma.start_reporting_thread_in_master+
    # configuration option.
    #
    # == High Security Mode
    #
    # Only +NewRelic::Agent.record_metric+ is used. No custom events or custom
    # attributes are recorded, and the sampled values are integers with no
    # request, query, or user data, so the plugin is fully functional under
    # High Security Mode.
    class PumaStatsSampler
      # Raised when Puma's +stats+ returns a Hash whose shape we don't
      # recognize (no +:worker_status+ and no top-level worker keys). Lets
      # +fetch_metrics+'s existing rescue route the case through the
      # throttled sample-failure path instead of silently recording nothing.
      class UnrecognizedStatsError < StandardError; end

      METRIC_NAMESPACE = 'Puma'
      # Per-worker keys reported by +Puma::Server#stats+ and surfaced through
      # +Puma::Launcher#stats+. +requests_count+ is a cumulative counter (use
      # +rate()+ in NRQL); the rest are point-in-time gauges.
      WORKER_STAT_KEYS = %i[backlog running pool_capacity max_threads requests_count].freeze
      # Puma's +pool_capacity+ is the number of additional requests the pool
      # can accept right now: idle (waiting) threads plus unspawned threads
      # still allowed up to +max_threads+ (i.e. +waiting + (max - spawned)+).
      # Reporting it as +spare_thread_capacity+ makes that meaning explicit.
      METRIC_NAME_OVERRIDES = {pool_capacity: 'spare_thread_capacity'}.freeze
      # Mirrors the +puma.sample_rate+ default in
      # +lib/new_relic/agent/configuration/default_source.rb+; used only if that
      # config value is missing or non-positive.
      DEFAULT_SAMPLE_RATE = 15
      # When +stats+ fails repeatedly, log the first failure and then only every
      # Nth occurrence to avoid flooding the Puma master log.
      LOG_FAILURE_INTERVAL = 10
      # Floor on time between failure logs: even with exponential backoff
      # suppressing per-iteration logs, a persistent failure is re-logged at
      # least this often so operators see it within ~5 min instead of ~14
      # (15 + 30 + 60 + 6*120 seconds for 9 waits between consecutive
      # failures 1..10 at the default 15 s sample rate, with the backoff
      # capped at 2**3 = 8 intervals).
      LOG_FAILURE_TIME_FLOOR_SECONDS = 300
      # Largest exponent used for exponential backoff after consecutive sampling
      # failures, i.e. the wait grows up to 2**3 = 8 sample intervals.
      BACKOFF_EXPONENT_CAP = 3

      def initialize(launcher)
        @launcher = launcher
        @sample_rate = resolve_sample_rate
        @lock = Mutex.new
        @stop_signal = ConditionVariable.new
        @running = false
        @stopped = false
        @consecutive_failures = 0
        @last_failure_logged_at = nil
        @consecutive_report_failures = 0
        @last_report_failure_logged_at = nil
      end

      # Runs the sampling loop. Intended to be called from the Puma plugin's
      # +in_background+ block, which executes in the master process. Blocks
      # until #stop is called from a Puma lifecycle event (+:state+ in single
      # mode, +:before_restart+ / +:after_stopped+ on the master in clustered
      # mode). Single-shot: after the loop exits (cleanly or via the rescue
      # path below) the sampler is done; the plugin instantiates one sampler
      # per Puma boot, so #start is never re-entered on the same instance.
      def start
        return unless ensure_master_is_reporting

        @lock.synchronize do
          return if @stopped # #stop may have been called before we started

          @running = true
          begin
            while @running
              sample
              # Wait one interval (longer after repeated failures), releasing
              # the lock, or until #stop signals us for immediate shutdown.
              # Re-check @running because the signal may have flipped it.
              @stop_signal.wait(@lock, next_wait_interval) if @running
            end
          ensure
            # Even if an exception aborts the loop, leave @running consistent
            # so a future #stop is a clean no-op rather than racing a stale
            # truthy flag.
            @running = false
          end
        end
      rescue => e
        # Puma's +fire_background+ uses a bare +Thread.new+ with no rescue, so
        # any exception escaping here would silently kill the sampler thread.
        # Mirror +Threading::AgentThread.create+: log StandardError, log and
        # re-raise Exception (so interrupts still propagate).
        ::NewRelic::Agent.logger.error('NewRelic Puma plugin sampler thread exited with error', e)
      rescue Exception => e
        ::NewRelic::Agent.logger.error('NewRelic Puma plugin sampler thread exited with exception. Re-raising in case of interrupt.', e)
        raise
      end

      # Signals the sampling loop to exit. Thread-safe: #stop runs on the Puma
      # event thread while #start's loop runs on the background thread.
      def stop
        @lock.synchronize do
          @running = false
          @stopped = true
          @stop_signal.signal
        end
      end

      private

      def sample
        metrics = fetch_metrics
        return unless metrics

        report_metrics(metrics)
      end

      # Fetches and aggregates Puma stats. Returns the metric Hash on success
      # or nil if Puma's +stats+ call (or parsing/aggregation) raised. Failures
      # here count toward the sampling backoff because they likely indicate
      # Puma-side trouble. Returns nil rather than raising so #sample can keep
      # the recording path separate.
      def fetch_metrics
        stats = @launcher.stats
        # Newer Puma returns a Hash; older versions return a JSON string. Parse
        # with symbolize_names so keys match WORKER_STAT_KEYS either way.
        stats = JSON.parse(stats, symbolize_names: true) unless stats.is_a?(Hash)
        metrics = aggregate(stats)
        @consecutive_failures = 0
        metrics
      rescue => e
        @consecutive_failures += 1
        log_sample_failure(e)
        nil
      end

      # Collapses Puma's stats into a flat metric => summed-value hash. Handles
      # both clustered mode (a +:worker_status+ array) and single mode (the
      # thread-pool keys at the top level). In clustered mode the per-worker
      # values are summed, giving cluster-wide totals (e.g. +pool_capacity+
      # becomes the cluster-wide spare thread capacity).
      #
      # Sparse data (a known shape with missing inner keys, e.g. a worker
      # without +:last_status+) is tolerated and yields zeros for the absent
      # metrics. A completely unrecognized shape (neither +:worker_status+
      # nor any +WORKER_STAT_KEYS+ at the top level) raises so the caller
      # surfaces it to operators instead of silently reporting nothing.
      def aggregate(stats)
        metrics = Hash.new(0)

        # +:worker_status: []+ (empty array) is intentionally a recognized
        # shape: a clustered master observed before its workers have booted
        # produces it briefly during startup. Tightening this to require a
        # non-empty array would log an UnrecognizedStatsError on every Puma
        # boot. The cost is ~15 s of misleading-but-self-correcting zero
        # metrics during boot, which is preferable to false-positive errors
        # in normal operation.
        if stats[:worker_status]
          metrics[:workers] = stats[:workers].to_i
          stats[:worker_status].each do |worker|
            last_status = worker[:last_status] || {}
            WORKER_STAT_KEYS.each do |key|
              metrics[key] += last_status[key].to_i if last_status.key?(key)
            end
          end
        elsif WORKER_STAT_KEYS.any? { |key| stats.key?(key) }
          WORKER_STAT_KEYS.each do |key|
            metrics[key] += stats[key].to_i if stats.key?(key)
          end
        else
          raise UnrecognizedStatsError,
            "Puma stats had neither :worker_status nor any of #{WORKER_STAT_KEYS.inspect} " \
            "(keys: #{stats.keys.inspect})"
        end

        metrics
      end

      # Records the aggregated metrics. A failure here is the agent's metric
      # store misbehaving, not Puma's; log it distinctly and do not count it
      # toward the sampling backoff (which is for Puma-side trouble). A
      # partial write is acceptable: any metric already recorded reaches New
      # Relic on the next harvest. Logging is throttled like sample failures
      # so a persistently broken metric store does not flood the master log
      # every sample interval.
      #
      # Asymmetry note: unlike +fetch_metrics+, this path does NOT extend
      # +next_wait_interval+ on failure. Puma-side trouble is a signal to back
      # off polling Puma; a metric-store outage isn't — keep sampling at the
      # configured rate so recording resumes immediately once the store
      # recovers. Don't "fix" this by merging the two counters.
      def report_metrics(metrics)
        metrics.each do |key, value|
          name = METRIC_NAME_OVERRIDES.fetch(key, key)
          ::NewRelic::Agent.record_metric("#{METRIC_NAMESPACE}/#{name}", value)
        end
        @consecutive_report_failures = 0
      rescue => e
        @consecutive_report_failures += 1
        log_report_failure(e)
      end

      # Seconds to wait before the next sample. Backs off exponentially (capped)
      # while stats are failing so a persistent failure doesn't hammer Puma or
      # flood the log; resets to the configured rate after a successful sample.
      def next_wait_interval
        return @sample_rate if @consecutive_failures.zero?

        exponent = [@consecutive_failures - 1, BACKOFF_EXPONENT_CAP].min
        @sample_rate * (2**exponent)
      end

      # The master's agent never started its harvest thread (deferred for the
      # forking dispatcher), so force it up so recorded metrics are delivered.
      # Returns true if reporting is ready (or intentionally disabled), false if
      # the attempt failed, in which case the caller skips sampling rather than
      # silently collecting metrics that will never be sent.
      def ensure_master_is_reporting
        return true unless ::NewRelic::Agent.config[:'puma.start_reporting_thread_in_master']

        ::NewRelic::Agent.after_fork(force_reconnect: true)
        true
      rescue => e
        ::NewRelic::Agent.logger.error( \
          'Unable to start the New Relic reporting thread in the Puma master; Puma metrics ' \
          "will not be sampled: #{e.class} - #{e.message}"
        )
        ::NewRelic::Agent.logger.log_exception(:debug, e)
        false
      end

      # Logs the first failure, every Nth subsequent failure, and any failure
      # that has not been logged in LOG_FAILURE_TIME_FLOOR_SECONDS. Without
      # the time floor, exponential backoff stretches the "every Nth" cadence
      # to ~14 minutes; the floor caps that at ~5 minutes so a persistent
      # failure is re-surfaced even while backoff is sparse.
      def log_sample_failure(e)
        now = monotonic_now
        return unless should_log?(@consecutive_failures, @last_failure_logged_at, now)

        ::NewRelic::Agent.logger.error( \
          "Error sampling Puma stats (consecutive failures: #{@consecutive_failures}): " \
          "#{e.class} - #{e.message}"
        )
        ::NewRelic::Agent.logger.log_exception(:debug, e)
        @last_failure_logged_at = now
      end

      # Mirrors +log_sample_failure+ for record_metric failures, throttled
      # against its own counter so a metric-store outage does not flood the
      # master log at every sample interval.
      def log_report_failure(e)
        now = monotonic_now
        return unless should_log?(@consecutive_report_failures, @last_report_failure_logged_at, now)

        ::NewRelic::Agent.logger.error( \
          'Error recording Puma timeslice metrics ' \
          "(consecutive failures: #{@consecutive_report_failures}): #{e.class} - #{e.message}"
        )
        ::NewRelic::Agent.logger.log_exception(:debug, e)
        @last_report_failure_logged_at = now
      end

      def should_log?(consecutive, last_logged_at, now)
        return true if consecutive == 1
        return true if (consecutive % LOG_FAILURE_INTERVAL).zero?
        return true if time_floor_elapsed?(last_logged_at, now)

        false
      end

      def time_floor_elapsed?(last_logged_at, now)
        return false unless last_logged_at

        (now - last_logged_at) >= LOG_FAILURE_TIME_FLOOR_SECONDS
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def resolve_sample_rate
        rate = ::NewRelic::Agent.config[:'puma.sample_rate'].to_i
        rate.positive? ? rate : DEFAULT_SAMPLE_RATE
      end
    end
  end
end
