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
    # spare capacity, and configured max threads). Worker processes have no
    # reliable handle to their own server statistics from a background thread
    # (+Puma.stats_object+ is set only in the master and +Puma::Server.current+
    # is request-thread-local), so sampling must happen in the master. That
    # rules out a harvest-driven Sampler, whose +poll+ runs only on the
    # per-worker harvest thread.
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
    # attributes are recorded, and the sampled values are integer gauges with
    # no request, query, or user data, so the plugin is fully functional under
    # High Security Mode.
    class PumaStatsSampler
      METRIC_NAMESPACE = 'Puma'
      # Per-worker thread-pool metrics reported by +Puma::Server#stats+.
      WORKER_STAT_KEYS = %i[backlog running pool_capacity max_threads].freeze
      DEFAULT_SAMPLE_RATE = 15

      def initialize(launcher)
        @launcher = launcher
        @sample_rate = resolve_sample_rate
        @last_sample_at = nil
        @running = false
      end

      # Runs the sampling loop. Intended to be called from the Puma plugin's
      # +in_background+ block, which executes in the master process.
      def start
        @running = true
        ensure_master_is_reporting

        while @running
          sleep(1)
          next unless should_sample?

          @last_sample_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sample
        end
      end

      # Signals the sampling loop to exit. Registered against Puma's +:state+
      # lifecycle events for +halt+, +restart+, and +stop+.
      def stop
        @running = false
      end

      def should_sample?
        return true if @last_sample_at.nil?

        Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_sample_at >= @sample_rate
      end

      def sample
        stats = @launcher.stats
        stats = JSON.parse(stats, symbolize_names: true) unless stats.is_a?(Hash)
        report_metrics(aggregate(stats))
      rescue => e
        ::NewRelic::Agent.logger.error("Error sampling Puma stats: #{e.class} - #{e.message}")
      end

      # Collapses Puma's stats into a flat metric => summed-value hash.
      # Handles both clustered mode (a +:worker_status+ array) and single mode
      # (the thread-pool keys at the top level).
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

      private

      def report_metrics(metrics)
        metrics.each do |key, value|
          ::NewRelic::Agent.record_metric("#{METRIC_NAMESPACE}/#{key}", value)
        end
      end

      # The master's agent never started its harvest thread (deferred for the
      # forking dispatcher), so force it up so recorded metrics are delivered.
      def ensure_master_is_reporting
        return unless ::NewRelic::Agent.config[:'puma.start_reporting_thread_in_master']

        ::NewRelic::Agent.after_fork(force_reconnect: true)
      rescue => e
        ::NewRelic::Agent.logger.error( \
          "Unable to start New Relic reporting thread in the Puma master: #{e.class} - #{e.message}"
        )
      end

      def resolve_sample_rate
        rate = ::NewRelic::Agent.config[:'puma.sample_rate'].to_i
        rate.positive? ? rate : DEFAULT_SAMPLE_RATE
      end
    end
  end
end
