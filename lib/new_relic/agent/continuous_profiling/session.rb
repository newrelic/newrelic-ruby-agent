# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/continuous_profiling/stack_prof_sampler'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Owns the lifecycle of continuous profiling: starting/stopping StackProf on a
      # dedicated background thread, and reacting to agent shutdown. Server-side config
      # (evaluate_and_apply) and agent commands (handle_start_command/handle_stop_command)
      # are independent activation paths, kept that way since it's not yet settled which
      # one the collector will standardize on.
      class Session
        ENABLED_METRIC = 'Supportability/Ruby/Profiling/Enabled'
        DISABLED_METRIC = 'Supportability/Ruby/Profiling/Disabled'
        SAMPLING_DURATION_METRIC = 'Supportability/Ruby/Profiling/Sampling/Duration'
        SEGMENT_RANGES_LIMIT_METRIC = 'Supportability/Ruby/Profiling/SegmentRanges/LimitExceeded'
        SKIPPED_NOT_CONNECTED_METRIC = 'Supportability/Ruby/Profiling/Export/SkippedNotConnected'

        # Accumulates across all transactions within one harvest_period. Capped like other
        # per-harvest buffers -- this is best-effort correlation data, so a hard cap is
        # enough; no need for reservoir sampling.
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

          # Wall-clock range of every qualifying segment, matched against sample
          # timestamps in ProfileEncoder.
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
          thread_to_join = @lock.synchronize do
            return unless @running

            @running = false
            @cv.broadcast
            unsubscribe_from_transaction_hooks
            @thread
          end

          # Only cleared below if still current -- guards against a concurrent start()
          # clobbering @thread, and against losing the reference on a join timeout.
          if thread_to_join&.join(harvest_period + 1)
            @lock.synchronize { @thread = nil if @thread.equal?(thread_to_join) }
          else
            NewRelic::Agent.logger.warn(
              'Timed out waiting for continuous profiling thread to stop; it may still be running'
            )
          end
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

        # Runs on every :start_transaction while subscribed, so must stay cheap when no fork
        # happened. StackProf resets its own C-level running state on fork via pthread_atfork,
        # so only @running/@thread (stale copies from the parent) need recovering here.
        def restart_if_forked
          return unless @running && @starting_pid != Process.pid

          NewRelic::Agent.logger.debug(
            "Restarting continuous profiling in forked process #{Process.pid} (parent #{Process.ppid})"
          )
          reset_state_after_fork
          start
        end

        def reset_state_after_fork
          @lock = Mutex.new
          @cv = ConditionVariable.new
          @running = false
          @sampler_active = false
          @thread = nil
          @segment_ranges = []
          @segment_ranges_lock = Mutex.new
        end

        # Segments shorter than one sample_period are skipped (unlikely to ever match a
        # tick, and would otherwise bound how much @segment_ranges can grow); the root is
        # always kept as a fallback. The @running check guards a narrow window in #stop
        # where this handler hasn't been unsubscribed yet.
        def on_transaction_finished
          return unless @running

          txn = Tracer.current_transaction
          return unless txn

          trace_id = txn.trace_id
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

        def stackprof_present?
          defined?(StackProf) ? true : false
        end

        def protobuf_present?
          defined?(Google::Protobuf) ? true : false
        end

        def gems_present?
          stackprof_present? && protobuf_present?
        end

        # Only the conditions that are actually unmet, so the logged/raised message
        # says why *this* agent can't run it, not a static list of every requirement.
        def unsupported_reasons
          reasons = []
          reasons << 'the stackprof gem is not installed' unless stackprof_present?
          reasons << 'the google-protobuf gem is not installed' unless protobuf_present?
          reasons << 'JRuby is not supported' if NewRelic::LanguageSupport.jruby?
          reasons << 'high security mode is enabled' if NewRelic::Agent.config[:high_security]
          reasons
        end

        def unsupported_message
          "Continuous profiling is not available: #{unsupported_reasons.join(', ')}."
        end

        def raise_command_error(msg)
          raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new(msg)
        end

        def raise_unsupported_error
          msg = unsupported_message
          NewRelic::Agent.logger.warn(msg)
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
          elsif NewRelic::Agent.config[:'profiling.enabled'] && !supported?
            NewRelic::Agent.logger.warn(unsupported_message)
          end
        end

        # Required by every activation path, including handle_start_command -- deliberately
        # not gated on profiling.enabled, so the agent command works independently of config/SSC.
        def supported?
          !NewRelic::Agent.config[:high_security] && !NewRelic::LanguageSupport.jruby? && gems_present?
        end

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

        # Returns false when woken because stop() was called, signaling run_loop's final iteration.
        def wait_for_next_tick_or_stop
          @lock.synchronize do
            @cv.wait(@lock, harvest_period) if @running
            @running
          end
        end

        # @sampler_active is only touched here on the run_loop thread, guarding against
        # double-collecting if a harvest already ran for this tick.
        def harvest_and_send
          return unless @sampler_active

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @sampler_active = false
          report = collect_and_restart_sampler
          report[:segment_ranges] = drain_segment_ranges
          NewRelic::Agent.record_metric(SAMPLING_DURATION_METRIC, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
          NewRelic::Agent.logger.debug(
            "Continuous profiling collected #{report[:samples]} sample(s) in #{report[:mode]} mode"
          )
          encode_and_export(report)
        rescue => e
          NewRelic::Agent.logger.error('Error harvesting continuous profiling data', e)
        end

        # Restarts sampling immediately after collection, before the (network-bound)
        # encode_and_export -- otherwise every harvest would leave a sampling gap for as
        # long as the export takes. The tradeoff: an encode/export that's slow enough will
        # leave a few of its own frames in the *next* report.
        def collect_and_restart_sampler
          @sampler.stop_and_collect
        ensure
          if running?
            @sampler.start
            @sampler_active = true
          end
        end

        # Split out so tests can stub this one seam instead of requiring google-protobuf.
        # Drops the harvest's data if not connected yet -- the next tick tries again.
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
