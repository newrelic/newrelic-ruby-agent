# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/continuous_profiling/stack_prof_sampler'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Server-side config and agent commands are independent activation paths; which one the
      # collector will standardize on isn't settled, so neither is folded into the other.
      class Session
        ENABLED_METRIC = 'Supportability/Ruby/Profiling/Enabled'
        DISABLED_METRIC = 'Supportability/Ruby/Profiling/Disabled'
        PROFILE_TYPE_METRIC_PREFIX = 'Supportability/Ruby/Profiling'
        DURATION_METRIC = 'Supportability/Ruby/Profiling/Duration'
        SAMPLING_DURATION_METRIC = 'Supportability/Ruby/Profiling/Sampling/Duration'
        SEGMENT_RANGES_LIMIT_METRIC = 'Supportability/Ruby/Profiling/SegmentRanges/LimitExceeded'
        SKIPPED_NOT_CONNECTED_METRIC = 'Supportability/Ruby/Profiling/Export/SkippedNotConnected'

        MAX_SEGMENT_RANGES = 10_000

        def initialize(events)
          @events = events
          @lock = Mutex.new
          @fork_lock = Mutex.new
          @cv = ConditionVariable.new
          @running = false
          @thread = nil
          @delay_thread = nil
          @started_at = nil
          @starting_pid = nil
          @cancel_delayed_start = false
          @sampler = StackProfSampler.new
          @transaction_hooks_subscribed = false
          @start_transaction_handler = nil
          @transaction_finished_handler = nil
          clear_segment_ranges

          @events&.subscribe(:server_source_configuration_added) { evaluate_and_apply }
          @events&.subscribe(:before_shutdown) { stop }
        end

        def maybe_start
          return unless enabled?

          delayed_start
        end

        def running?
          @lock.synchronize { @running }
        end

        def start(from_delayed_start: false)
          @lock.synchronize do
            @delay_thread = nil if from_delayed_start && @delay_thread.equal?(Thread.current)

            return if @running
            # A stop() can land after this delayed start's sleep has elapsed, too late for the
            # kill in #stop to reach it -- without the flag the stop would be silently undone.
            return if from_delayed_start && (@cancel_delayed_start || !enabled?)

            @starting_pid = Process.pid

            unless @sampler.start
              NewRelic::Agent.logger.warn(
                'Continuous profiling could not start: StackProf is already running, started by ' \
                'something other than this agent.'
              )
              return
            end

            @running = true
            @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @thread = Threading::AgentThread.create('Continuous Profiling') { run_loop }
            subscribe_to_transaction_hooks
          end
          NewRelic::Agent.increment_metric(ENABLED_METRIC)
          NewRelic::Agent.increment_metric(profile_type_metric)
        end

        def stop(record_duration: false)
          thread_to_join = @lock.synchronize do
            # Cancelled here, before the @running guard below, so a pending delayed start
            # (profiling.delay not yet elapsed -- @running still false) is cancelled too.
            @cancel_delayed_start = true
            if @delay_thread
              @delay_thread.kill
              @delay_thread = nil
            end

            return unless @running

            record_duration_metric if record_duration
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

        def handle_start_command(agent_command)
          raise_unsupported_error unless supported?
          raise_already_started_error if running?

          start
        end

        def handle_stop_command(agent_command)
          stop
        end

        # Replaces only the locks, which may be inherited mid-hold from the parent's profiling
        # thread; @running/@starting_pid/@thread are left for restart_if_forked to detect and repair.
        def reset_after_fork_from_parent_thread
          @lock = Mutex.new
          @fork_lock = Mutex.new
          @segment_ranges_lock = Mutex.new
        end

        # restart_if_forked can't cover a fork mid-profiling.delay: the delay thread doesn't survive
        # it, and the transaction hooks it rides on are only subscribed once a session is running.
        def after_fork
          was_running = @running

          @fork_lock.synchronize do
            reset_state_after_fork

            unless NewRelic::Agent.config[:restart_thread_in_children]
              NewRelic::Agent.logger.debug(
                "Not restarting continuous profiling in forked process #{Process.pid}: " \
                'restart_thread_in_children is disabled'
              )
              @lock.synchronize { unsubscribe_from_transaction_hooks }
              return
            end

            @cancel_delayed_start = false
            was_running && supported? ? start : maybe_start
          end
        end

        private

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

        def restart_if_forked
          return unless forked?

          @fork_lock.synchronize do
            return unless forked?

            unless NewRelic::Agent.config[:restart_thread_in_children]
              # Without the teardown below, inherited hooks would keep buffering segment ranges
              # that no profiling thread is left to drain.
              NewRelic::Agent.logger.debug(
                "Not restarting continuous profiling in forked process #{Process.pid}: " \
                'restart_thread_in_children is disabled'
              )
              reset_state_after_fork
              @lock.synchronize { unsubscribe_from_transaction_hooks }
              return
            end

            NewRelic::Agent.logger.debug(
              "Restarting continuous profiling in forked process #{Process.pid} (parent #{Process.ppid})"
            )
            reset_state_after_fork
            start
          end
        end

        def forked?
          @running && @starting_pid != Process.pid
        end

        def reset_state_after_fork
          @lock = Mutex.new
          @cv = ConditionVariable.new
          @running = false
          @thread = nil
          @delay_thread = nil
          @started_at = nil
          clear_segment_ranges
        end

        def clear_segment_ranges
          @segment_ranges = []
          @segment_ranges_lock = Mutex.new
        end

        # trace_id_if_generated, not trace_id, so profiling never forces a trace_id into existence.
        def on_transaction_finished
          return unless @running

          txn = Tracer.current_transaction
          return unless txn

          trace_id = txn.trace_id_if_generated
          return unless trace_id

          root = txn.initial_segment
          min_duration = NewRelic::Agent.config[:'profiling.sample_period']

          @segment_ranges_lock.synchronize do
            if @segment_ranges.size >= MAX_SEGMENT_RANGES
              NewRelic::Agent.increment_metric(SEGMENT_RANGES_LIMIT_METRIC)
              return
            end

            dropped = false

            txn.segments.each do |segment|
              next unless segment.finished? && (segment.equal?(root) || segment.duration >= min_duration)

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

        def evaluate_and_apply
          if enabled? && !running?
            delayed_start
          elsif !enabled? && running?
            stop(record_duration: true)
          elsif NewRelic::Agent.config[:'profiling.enabled'] && !supported?
            NewRelic::Agent.logger.warn(unsupported_message)
          end
        end

        # handle_start_command, restart_if_forked and after_fork call #start directly: a delay is
        # wrong for an explicit on-demand start or a fork repair.
        def delayed_start
          delay_ms = NewRelic::Agent.config[:'profiling.delay'].to_i
          return start if delay_ms <= 0

          @lock.synchronize do
            return if @running || @delay_thread

            @cancel_delayed_start = false
            @delay_thread = Threading::AgentThread.create('Continuous Profiling Delay') do
              sleep(delay_ms / 1000.0)
              start(from_delayed_start: true)
            end
          end
        end

        def supported?
          !NewRelic::Agent.config[:high_security] && !NewRelic::LanguageSupport.jruby? && gems_present?
        end

        def enabled?
          NewRelic::Agent.config[:'profiling.enabled'] && supported?
        end

        def profile_type_metric
          "#{PROFILE_TYPE_METRIC_PREFIX}/#{NewRelic::Agent.config[:'profiling.include'].capitalize}"
        end

        def harvest_period
          NewRelic::Agent.config[:'profiling.harvest_period']
        end

        def duration_seconds
          ms = NewRelic::Agent.config[:'profiling.duration'].to_i
          ms > 0 ? ms / 1000.0 : nil
        end

        def duration_elapsed?
          ds = duration_seconds
          ds && @started_at && (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) >= ds
        end

        def run_loop
          loop do
            keep_going = wait_for_next_tick_or_stop

            # Checked before the harvest so @running is already false, otherwise
            # collect_and_restart_sampler's ensure restarts the sampler nothing will drain.
            if keep_going && duration_elapsed?
              finish_due_to_duration
              keep_going = false
            end

            harvest_and_send

            # A stop() landing mid-harvest has already left the sampler drained and not
            # restarted, so another pass would collect nothing (StackProf.results is nil).
            break unless keep_going && running?
          end
        ensure
          abandon_sampling if running?
        end

        # For an abnormal exit (a non-StandardError escaping harvest_and_send, a Thread#kill):
        # unattended raw-mode sampling grows forever, and #start can't take over until it stops.
        def abandon_sampling
          @sampler.stop
          @lock.synchronize do
            @running = false
            @thread = nil
            unsubscribe_from_transaction_hooks
          end
          NewRelic::Agent.logger.error('The continuous profiling thread exited unexpectedly; sampling stopped.')
          NewRelic::Agent.increment_metric(DISABLED_METRIC)
        end

        # Duplicates #stop rather than calling it because this runs on @thread, which cannot join
        # itself. A later #stop() early-returns on @running, so Disabled is not double-counted.
        def finish_due_to_duration
          @lock.synchronize do
            record_duration_metric
            @running = false
            @thread = nil
            unsubscribe_from_transaction_hooks
          end
          NewRelic::Agent.logger.debug('Continuous profiling duration elapsed; stopping.')
          NewRelic::Agent.increment_metric(DISABLED_METRIC)
        end

        # Deliberately not called on ordinary shutdown: only a duration elapsing or a server-side
        # disable counts as a measured end for this metric.
        def record_duration_metric
          return unless @started_at

          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).to_i
          NewRelic::Agent.record_metric(DURATION_METRIC, elapsed_ms)
        end

        def next_wait_seconds
          ds = duration_seconds
          return harvest_period unless ds

          remaining = ds - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at)
          [remaining.clamp(0, Float::INFINITY), harvest_period].min
        end

        def wait_for_next_tick_or_stop
          @lock.synchronize do
            @cv.wait(@lock, next_wait_seconds) if @running
            @running
          end
        end

        def harvest_and_send
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

        # Sampling restarts in the ensure, ahead of the network-bound export, so a harvest leaves
        # no sampling gap for as long as the export takes.
        def collect_and_restart_sampler
          @sampler.stop_and_collect
        ensure
          if running? && !@sampler.start
            NewRelic::Agent.logger.warn(
              'Continuous profiling could not restart sampling: StackProf is already running, ' \
              'started by something other than this agent. Will retry next harvest.'
            )
          end
        end

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
