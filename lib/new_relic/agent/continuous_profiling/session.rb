# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/continuous_profiling/stack_prof_sampler'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Owns the lifecycle of continuous profiling: starting/stopping StackProf on a
      # dedicated background thread, and reacting to agent shutdown. Two activation
      # triggers are wired in since the collector-driven mechanism isn't finalized:
      # server-side config (placeholder, via evaluate_and_apply) and agent commands
      # (handle_start_command/handle_stop_command, dispatched from
      # Commands::AgentCommandRouter like the legacy thread profiler). Whichever the
      # collector team settles on stays; the other may not survive to GA.
      #
      # Unlike the legacy thread profiler's trie, StackProf results are already a
      # complete cumulative report each time they're pulled, so each harvest tick simply
      # stops, collects, and restarts the sampler -- no aggregation needed.
      #
      # Background threads don't survive fork, so a process that forks after profiling
      # started (Puma cluster mode, Passenger, Resque, daemonizing) silently loses this
      # thread in every child. Recovered the way Harvester recovers its reporting thread:
      # on the first transaction in any process, check whether the pid profiling last
      # started in still matches, and if not, restart.
      #
      # The per-transaction hooks are only subscribed while running (see
      # subscribe_to_transaction_hooks), so idle installs -- the common case, since this
      # is opt-in -- don't pay for an EventListener dispatch on every transaction.
      class Session
        ENABLED_METRIC = 'Supportability/Ruby/Profiling/Enabled'
        DISABLED_METRIC = 'Supportability/Ruby/Profiling/Disabled'
        SAMPLING_DURATION_METRIC = 'Supportability/Ruby/Profiling/Sampling/Duration'
        SEGMENT_RANGES_LIMIT_METRIC = 'Supportability/Ruby/Profiling/SegmentRanges/LimitExceeded'
        SKIPPED_NOT_CONNECTED_METRIC = 'Supportability/Ruby/Profiling/Export/SkippedNotConnected'

        # Accumulates across *all* transactions between harvest ticks, so unbounded
        # throughput within one harvest_period (not transaction duration) is the growth axis.
        # Capped like other per-harvest buffers (EventBuffer/PrioritySampledBuffer) -- this is
        # best-effort correlation data, so a hard cap is enough; no need for reservoir sampling.
        MAX_SEGMENT_RANGES = 10_000

        def initialize(events)
          @events = events
          @lock = Mutex.new
          @cv = ConditionVariable.new
          @running = false
          @sampler_active = false
          @thread = nil
          @starting_pid = nil
          @sampler = StackProfSampler.new
          @transaction_hooks_subscribed = false
          @start_transaction_handler = nil
          @transaction_finished_handler = nil

          # Per-sample correlation signal: wall-clock range of every qualifying segment
          # (not just the root) of each transaction that finished during the harvest
          # window, matched against sample timestamps in ProfileEncoder (see
          # drain_segment_ranges).
          @segment_ranges = []
          @segment_ranges_lock = Mutex.new

          @events&.subscribe(:server_source_configuration_added) { evaluate_and_apply }
          @events&.subscribe(:before_shutdown) { stop }
        end

        # Called once at start-up, after DependencyDetection has confirmed the required
        # gems are present and the platform is supported.
        def maybe_start
          return unless enabled?

          start
        end

        def running?
          @lock.synchronize { @running }
        end

        def start
          @lock.synchronize do
            return if @running

            @starting_pid = Process.pid
            @sampler.start
            @sampler_active = true
            @running = true
            @thread = Threading::AgentThread.create('Continuous Profiling') { run_loop }
            subscribe_to_transaction_hooks
          end
          NewRelic::Agent.increment_metric(ENABLED_METRIC)
        end

        def stop
          @lock.synchronize do
            return unless @running

            @running = false
            @cv.broadcast
            unsubscribe_from_transaction_hooks
          end
          @thread&.join(harvest_period + 1)
          @thread = nil
          NewRelic::Agent.increment_metric(DISABLED_METRIC)
        end

        # Agent-command activation. Registered as handlers in
        # Commands::AgentCommandRouter the same way the legacy thread profiler is.
        def handle_start_command(agent_command)
          raise_unsupported_error unless supported?
          raise_already_started_error if running?

          start
        end

        def handle_stop_command(agent_command)
          stop
        end

        private

        # Guarded so a fork-restart (start called again without going through stop -- see
        # restart_if_forked) doesn't double-subscribe.
        def subscribe_to_transaction_hooks
          return unless @events && !@transaction_hooks_subscribed

          @start_transaction_handler = @events.subscribe(:start_transaction) { restart_if_forked }
          @transaction_finished_handler = @events.subscribe(:transaction_finished) { on_transaction_finished }
          @transaction_hooks_subscribed = true
        end

        def unsubscribe_from_transaction_hooks
          return unless @events && @transaction_hooks_subscribed

          @events.unsubscribe(:start_transaction, @start_transaction_handler)
          @events.unsubscribe(:transaction_finished, @transaction_finished_handler)
          @transaction_hooks_subscribed = false
        end

        # Runs on every :start_transaction while subscribed, so must stay cheap when no
        # fork happened. StackProf resets its own C-level running state on fork via
        # pthread_atfork, so restarting the sampler here is always safe -- only
        # @running/@thread (copied from the parent, no longer accurate in the child) need
        # recovering.
        def restart_if_forked
          return unless @running && @starting_pid != Process.pid

          NewRelic::Agent.logger.debug(
            "Restarting continuous profiling in forked process #{Process.pid} (parent #{Process.ppid})"
          )
          @lock.synchronize { @running = false }
          @thread = nil
          start
        end

        # current_segment is already nil by :transaction_finished time; segments (never
        # cleared) is used instead. Segments under one sample_period are skipped (bounds
        # memory, unlikely to ever match a tick); the root is always kept as a fallback.
        #
        # The @running check here is a cheap belt-and-suspenders guard against a narrow
        # window in #stop (between flipping @running and this handler actually being
        # unsubscribed) -- without it, a range recorded in that window would otherwise
        # linger in @segment_ranges and pollute a later profiling session's first harvest.
        def on_transaction_finished
          return unless @running

          txn = Tracer.current_transaction
          return unless txn

          trace_id = txn.trace_id_if_generated
          root = txn.initial_segment
          min_duration = NewRelic::Agent.config[:'profiling.sample_period']

          candidates = txn.segments.select do |segment|
            segment.finished? && (segment.equal?(root) || segment.duration >= min_duration)
          end

          @segment_ranges_lock.synchronize do
            dropped = false

            candidates.each do |segment|
              if @segment_ranges.size >= MAX_SEGMENT_RANGES
                dropped = true
                break
              end

              @segment_ranges << [trace_id, segment.guid, segment.start_time, segment.end_time]
            end

            NewRelic::Agent.increment_metric(SEGMENT_RANGES_LIMIT_METRIC) if dropped
          end
        end

        def drain_segment_ranges
          @segment_ranges_lock.synchronize do
            ranges = @segment_ranges
            @segment_ranges = []
            ranges
          end
        end

        def gems_present?
          defined?(StackProf) && defined?(Google::Protobuf)
        end

        def raise_command_error(msg)
          raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new(msg)
        end

        def raise_unsupported_error
          msg = 'Continuous profiling is not available: requires the stackprof and google-protobuf gems, ' \
            'is not supported on JRuby, and is disabled while high security mode is enabled.'
          raise_command_error(msg)
        end

        def raise_already_started_error
          msg = 'Continuous profiling already in progress. Ignoring agent command to start another.'
          raise_command_error(msg)
        end

        # Placeholder for the real collector-driven activation mechanism: re-evaluates
        # whether profiling should run whenever server-side config is (re-)applied.
        def evaluate_and_apply
          if enabled? && !running?
            start
          elsif !enabled? && running?
            stop
          end
        end

        # Required by every activation path, including handle_start_command -- deliberately
        # not gated on profiling.enabled, so the agent command works independently of config/SSC.
        def supported?
          !NewRelic::Agent.config[:high_security] && !NewRelic::LanguageSupport.jruby? && gems_present?
        end

        # Config-driven activation (maybe_start, evaluate_and_apply) additionally requires
        # the profiling.enabled toggle.
        def enabled?
          NewRelic::Agent.config[:'profiling.enabled'] && supported?
        end

        def harvest_period
          NewRelic::Agent.config[:'profiling.harvest_period']
        end

        # Loops until stop() broadcasts, doing one harvest_and_send per tick plus exactly
        # one final one covering whatever's outstanding -- see wait_for_next_tick_or_stop.
        def run_loop
          loop do
            keep_going = wait_for_next_tick_or_stop
            harvest_and_send
            break unless keep_going
          end
        end

        # Returns true for a normal periodic tick, false when woken because stop() was
        # called -- the caller then knows this is the final iteration.
        def wait_for_next_tick_or_stop
          @lock.synchronize do
            @cv.wait(@lock, harvest_period) if @running
            @running
          end
        end

        # @sampler_active is only touched here on the run_loop thread (stop() only touches
        # @running), so the guard below is race-free: if a harvest already ran for this
        # tick -- e.g. it finished just as stop() flipped @running, and the loop comes back
        # around once more before breaking -- this is a no-op instead of double-collecting.
        def harvest_and_send
          return unless @sampler_active

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @sampler_active = false
          report = @sampler.stop_and_collect
          report[:segment_ranges] = drain_segment_ranges
          NewRelic::Agent.record_metric(SAMPLING_DURATION_METRIC, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
          NewRelic::Agent.logger.debug(
            "Continuous profiling collected #{report[:samples]} sample(s) in #{report[:mode]} mode"
          )
          encode_and_export(report)
        rescue => e
          NewRelic::Agent.logger.error('Error harvesting continuous profiling data', e)
        ensure
          if running?
            @sampler.start
            @sampler_active = true
          end
        end

        # Split out so tests can stub this one seam instead of the ProfileEncoder require
        # chain, which has a hard dependency on google-protobuf being loadable.
        #
        # profiles_data needs a connected redirect host. If not connected yet, drop this
        # harvest's data -- the next tick tries again.
        def encode_and_export(report)
          unless NewRelic::Agent.agent.connected?
            NewRelic::Agent.increment_metric(SKIPPED_NOT_CONNECTED_METRIC)
            NewRelic::Agent.logger.debug('Skipping continuous profiling export: agent is not connected')
            return
          end

          require 'new_relic/agent/continuous_profiling/profile_encoder'
          bytes = ProfileEncoder.encode(report)
          NewRelic::Agent.agent.service.profiles_data(bytes)
        end
      end
    end
  end
end
