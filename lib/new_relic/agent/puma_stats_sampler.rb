# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'

module NewRelic
  module Agent
    # Samples Puma's clustered server statistics from the master process and
    # records them as timeslice metrics under +Ruby/Puma/*+.
    #
    # Only the master exposes cluster-wide stats (per-worker thread-pool
    # backlog, running threads, +pool_capacity+, +max_threads+,
    # +requests_count+), so sampling happens there.
    #
    # This class restarts the harvest thread in the master via
    # +NewRelic::Agent.after_fork(force_reconnect: true)+ to deliver the
    # sampled metrics. The master then reports to New Relic as its own
    # instance.
    #
    # Records only integer gauges/counters via +NewRelic::Agent.record_metric+
    # (no request, query, or user data), so it is fully functional under High
    # Security Mode.
    #
    class PumaStatsSampler
      # Raised on an unrecognized stats shape: neither +:worker_status+ nor any
      # top-level worker keys. +fetch_metrics+ rescues it onto the throttled
      # sample-failure path, so a bad shape surfaces in the log instead of
      # silently recording nothing.
      class UnrecognizedStatsError < StandardError; end

      METRIC_NAMESPACE = 'Ruby/Puma'
      # Per-worker stat keys, summed across the cluster. +requests_count+ is a
      # cumulative counter (use +rate()+ in NRQL); the rest are point-in-time
      # gauges. +pool_capacity+ is spare request capacity: idle threads plus
      # unspawned threads still allowed up to +max_threads+.
      WORKER_STAT_KEYS = %i[backlog running pool_capacity max_threads requests_count].freeze
      # Runner metadata reported by +Puma::Runner#stats+ alongside (or, before
      # the runner's +Puma::Server+ exists, instead of) the per-worker keys.
      RUNNER_INFO_KEYS = %i[started_at versions].freeze
      DEFAULT_SAMPLE_RATE = 60
      LOG_FAILURE_INTERVAL = 10
      # Caps how long a persistent failure can go unlogged: forces a re-log once
      # ~5 min have elapsed, instead of waiting for the backed-off "every Nth"
      # cadence (~55 min at the default sample rate).
      LOG_FAILURE_TIME_FLOOR_SECONDS = 300
      # Caps backoff growth at 2**3 = 8 sample intervals.
      BACKOFF_EXPONENT_CAP = 3

      def initialize(stats_source)
        @stats_source = stats_source
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

      # Runs the sampling loop on the background thread the instrumentation
      # spawns in the master. Blocks until #stop is called from a Puma lifecycle
      # event. Single-shot: the instrumentation builds one sampler per Puma boot,
      # so #start is never re-entered on the same instance.
      def start
        return unless ensure_master_is_reporting

        @lock.synchronize do
          return if @stopped

          @running = true
          begin
            while @running
              sample
              # Wait one interval (releases the lock); #stop wakes us early.
              # Re-check @running because the signal may have flipped it.
              @stop_signal.wait(@lock, next_wait_interval) if @running
            end
          ensure
            # Keep @running consistent if the loop aborts via an exception.
            @running = false
          end
        end
      rescue => e
        # The instrumentation starts this loop on a bare +Thread.new+, so an
        # unhandled exception would silently kill the sampler thread. Log
        # StandardError; log and re-raise Exception so interrupts still propagate.
        ::NewRelic::Agent.logger.error('NewRelic Puma stats sampler thread exited with error', e)
      rescue Exception => e
        ::NewRelic::Agent.logger.error('NewRelic Puma stats sampler thread exited with exception. Re-raising in case of interrupt.', e)
        raise
      end

      # Thread-safe: #stop runs on the Puma event thread, #start on the
      # background thread.
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

      # Fetches and aggregates Puma stats. Returns the metric Hash on success or
      # nil on failure. Failures count toward the sampling backoff (likely
      # Puma-side trouble). Returns nil rather than raising so #sample can route
      # recording failures through their own counter.
      def fetch_metrics
        stats = @stats_source.stats
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
      # clustered mode (sums across +:worker_status+) and single mode (top-level
      # keys). Sparse data is tolerated; a completely unrecognized shape raises
      # so operators see a clear signal instead of silent zero metrics.
      def aggregate(stats)
        metrics = Hash.new(0)

        # Empty +:worker_status+ is intentional: a clustered master sampled before
        # its workers have spawned produces it briefly during boot. Requiring
        # non-empty would log an UnrecognizedStatsError on every Puma boot.
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
        elsif !stats.empty? && (stats.keys - RUNNER_INFO_KEYS).empty?
          # A single-mode runner sampled before its Puma::Server exists reports
          # only runner metadata: a recognized boot shape with nothing to record.
          # Strict (metadata keys only) so that if a Puma release renames the
          # per-worker keys, this branch still raises instead of silently treating
          # the renamed stats as harmless metadata.
        else
          raise UnrecognizedStatsError,
            "Puma stats had neither :worker_status nor any of #{WORKER_STAT_KEYS.inspect} " \
            "(keys: #{stats.keys.inspect})"
        end

        metrics
      end

      # Records the aggregated metrics. A failure here is the agent's metric
      # store, not Puma's; log distinctly (throttled) and don't count against
      # the sample backoff.
      #
      # Asymmetry: this path does NOT extend +next_wait_interval+ on failure.
      # A metric-store outage shouldn't slow Puma polling; recording should
      # resume immediately on recovery. Don't "fix" this by merging counters.
      def report_metrics(metrics)
        metrics.each do |key, value|
          ::NewRelic::Agent.record_metric("#{METRIC_NAMESPACE}/#{key}", value)
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

      # Force the agent's harvest thread up in the master (normally deferred
      # under forking dispatchers). Returns false on failure so the caller can
      # skip sampling rather than buffer metrics that will never be sent.
      def ensure_master_is_reporting
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
      # not logged within LOG_FAILURE_TIME_FLOOR_SECONDS.
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
      # against its own counter to avoid flooding the master log.
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
