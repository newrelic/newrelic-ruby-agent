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
      METRIC_NAMESPACE = 'Puma'
      # Per-worker keys reported by +Puma::Server#stats+ and surfaced through
      # +Puma::Launcher#stats+. +requests_count+ is a cumulative counter (use
      # +rate()+ in NRQL); the rest are point-in-time gauges.
      WORKER_STAT_KEYS = %i[backlog running pool_capacity max_threads requests_count].freeze
      # Puma's +pool_capacity+ is the number of threads currently free to take
      # work; summed across workers it is the cluster's total spare threads, so
      # it is reported under a name that conveys that meaning.
      METRIC_NAME_OVERRIDES = {pool_capacity: 'spare_thread_capacity'}.freeze
      # Mirrors the +puma.sample_rate+ default in
      # +lib/new_relic/agent/configuration/default_source.rb+; used only if that
      # config value is missing or non-positive.
      DEFAULT_SAMPLE_RATE = 15
      # When +stats+ fails repeatedly, log the first failure and then only every
      # Nth occurrence to avoid flooding the Puma master log.
      LOG_FAILURE_INTERVAL = 10
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
      end

      # Runs the sampling loop. Intended to be called from the Puma plugin's
      # +in_background+ block, which executes in the master process. Blocks
      # until #stop is called (from Puma's +:state+ event handler).
      def start
        return unless ensure_master_is_reporting

        @lock.synchronize do
          return if @stopped # #stop may have been called before we started

          @running = true
          while @running
            sample
            # Wait one interval (longer after repeated failures), releasing the
            # lock, or until #stop signals us for immediate shutdown. Re-check
            # @running because the signal may have flipped it.
            @stop_signal.wait(@lock, next_wait_interval) if @running
          end
        end
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
        stats = @launcher.stats
        # Newer Puma returns a Hash; older versions return a JSON string. Parse
        # with symbolize_names so keys match WORKER_STAT_KEYS either way.
        stats = JSON.parse(stats, symbolize_names: true) unless stats.is_a?(Hash)
        report_metrics(aggregate(stats))
        @consecutive_failures = 0
      rescue => e
        @consecutive_failures += 1
        log_sample_failure(e)
      end

      # Collapses Puma's stats into a flat metric => summed-value hash. Handles
      # both clustered mode (a +:worker_status+ array) and single mode (the
      # thread-pool keys at the top level). In clustered mode the per-worker
      # values are summed, giving cluster-wide totals (e.g. +pool_capacity+ is
      # the total spare thread capacity across all workers).
      def aggregate(stats)
        metrics = Hash.new(0)

        if stats[:worker_status]
          metrics[:workers] = stats[:workers].to_i
          stats[:worker_status].each do |worker|
            last_status = worker[:last_status] || {}
            WORKER_STAT_KEYS.each do |key|
              metrics[key] += last_status[key].to_i if last_status.key?(key)
            end
          end
        else
          WORKER_STAT_KEYS.each do |key|
            metrics[key] += stats[key].to_i if stats.key?(key)
          end
        end

        metrics
      end

      def report_metrics(metrics)
        metrics.each do |key, value|
          name = METRIC_NAME_OVERRIDES.fetch(key, key)
          ::NewRelic::Agent.record_metric("#{METRIC_NAMESPACE}/#{name}", value)
        end
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

      def log_sample_failure(e)
        return unless @consecutive_failures == 1 || (@consecutive_failures % LOG_FAILURE_INTERVAL).zero?

        ::NewRelic::Agent.logger.error( \
          "Error sampling Puma stats (consecutive failures: #{@consecutive_failures}): " \
          "#{e.class} - #{e.message}"
        )
        ::NewRelic::Agent.logger.log_exception(:debug, e)
      end

      def resolve_sample_rate
        rate = ::NewRelic::Agent.config[:'puma.sample_rate'].to_i
        rate.positive? ? rate : DEFAULT_SAMPLE_RATE
      end
    end
  end
end
