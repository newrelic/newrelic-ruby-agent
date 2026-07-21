# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/continuous_profiling/stack_prof_sampler'
require 'new_relic/agent/continuous_profiling/otlp_exporter'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Owns the lifecycle of continuous profiling: starting/stopping StackProf on a
      # dedicated background thread, and reacting to agent shutdown. Two activation
      # triggers are currently wired in, since the collector-driven mechanism isn't
      # finalized: server-side config changes (a placeholder, via evaluate_and_apply)
      # and agent commands (handle_start_command/handle_stop_command, dispatched from
      # Commands::AgentCommandRouter the same way the legacy thread profiler is). Both
      # may not survive to GA -- whichever the collector team settles on stays.
      #
      # Unlike the legacy thread profiler's BacktraceService/ThreadProfile trie, StackProf
      # results are already a complete cumulative report each time they're pulled, so no
      # aggregation step is needed here -- each harvest tick simply stops, collects, and
      # restarts the sampler.
      #
      # Background threads don't survive fork -- only the forking thread continues in the
      # child, so a process that forks after profiling has started (Puma cluster mode,
      # Passenger, Resque, or just daemonizing) silently loses this thread in every child.
      # Recovered the same way Harvester recovers the reporting thread: on the first
      # transaction in any process, check whether the pid profiling last started in still
      # matches, and if not, restart. This is dispatcher-agnostic -- no per-dispatcher fork
      # hook is needed -- but only fires once a transaction actually runs in the child.
      class Session
        ENABLED_METRIC = 'Supportability/Ruby/Profiling/Enabled'
        DISABLED_METRIC = 'Supportability/Ruby/Profiling/Disabled'
        SAMPLING_DURATION_METRIC = 'Supportability/Ruby/Profiling/Sampling/Duration'

        def initialize(events)
          @lock = Mutex.new
          @running = false
          @thread = nil
          @starting_pid = nil
          @sampler = StackProfSampler.new
          @exporter = OtlpExporter.new

          events&.subscribe(:server_source_configuration_added) { evaluate_and_apply }
          events&.subscribe(:before_shutdown) { stop }
          events&.subscribe(:start_transaction) { restart_if_forked }
        end

        # Called once at start-up, after DependencyDetection has already confirmed the
        # required gems are present and the platform is supported.
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
            @running = true
            @thread = Threading::AgentThread.create('Continuous Profiling') { run_loop }
          end
          NewRelic::Agent.increment_metric(ENABLED_METRIC)
        end

        def stop
          @lock.synchronize do
            return unless @running

            @running = false
          end
          @thread&.join(harvest_period + 1)
          @thread = nil
          NewRelic::Agent.increment_metric(DISABLED_METRIC)
        end

        # Agent-command activation. Registered as handlers in
        # Commands::AgentCommandRouter the same way the legacy thread profiler is.
        def handle_start_command(agent_command)
          raise_unsupported_error unless enabled?
          raise_already_started_error if running?

          start
        end

        def handle_stop_command(agent_command)
          stop
        end

        private

        # Called on every :start_transaction, so this must stay cheap in the common case
        # (no fork happened). StackProf itself already resets its own C-level running state
        # on fork via pthread_atfork, so restarting the sampler here is always safe -- the
        # only state that needs recovering is this object's own @running/@thread, which fork
        # copies from the parent but which no longer reflect reality in the child.
        def restart_if_forked
          return unless @running && @starting_pid != Process.pid

          NewRelic::Agent.logger.debug(
            "Restarting continuous profiling in forked process #{Process.pid} (parent #{Process.ppid})"
          )
          @lock.synchronize { @running = false }
          @thread = nil
          start
        end

        def gems_present?
          defined?(StackProf) && defined?(Google::Protobuf)
        end

        def raise_command_error(msg)
          raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new(msg)
        end

        def raise_unsupported_error
          msg = 'Continuous profiling is not available: requires the stackprof and google-protobuf gems, ' \
            "is not supported on JRuby, and requires config 'continuous_profiler.enabled' = true."
          raise_command_error(msg)
        end

        def raise_already_started_error
          msg = 'Continuous profiling already in progress. Ignoring agent command to start another.'
          raise_command_error(msg)
        end

        # Re-evaluates whether profiling should be running whenever server-side config is
        # (re-)applied, e.g. after connect/reconnect. This is the placeholder for the real
        # collector-driven activation mechanism, which is not yet decided.
        def evaluate_and_apply
          if enabled? && !running?
            start
          elsif !enabled? && running?
            stop
          end
        end

        # Gates every activation path (boot-time maybe_start, the SSC-reactive
        # evaluate_and_apply, and agent-command handle_start_command) on the same three
        # conditions, so none of them can call start without the gems StackProfSampler
        # needs actually being loaded -- e.g. a collector-driven SSC change flipping this on
        # for a customer who never added stackprof/google-protobuf to their Gemfile.
        def enabled?
          NewRelic::Agent.config[:'continuous_profiler.enabled'] && !NewRelic::LanguageSupport.jruby? && gems_present?
        end

        def harvest_period
          NewRelic::Agent.config[:'continuous_profiler.harvest_period']
        end

        def run_loop
          while running?
            sleep(harvest_period)
            harvest_and_send if running?
          end
        end

        def harvest_and_send
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          report = @sampler.stop_and_collect
          NewRelic::Agent.record_metric(SAMPLING_DURATION_METRIC, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
          NewRelic::Agent.logger.debug(
            "Continuous profiling collected #{report[:samples]} sample(s) in #{report[:mode]} mode"
          )
          encode_and_export(report)
        rescue => e
          NewRelic::Agent.logger.error('Error harvesting continuous profiling data', e)
        ensure
          @sampler.start if running?
        end

        # Split out from harvest_and_send so tests can stub this one seam instead of the
        # real ProfileEncoder require chain, which has a hard dependency on google-protobuf
        # being loadable and is therefore never required unconditionally.
        def encode_and_export(report)
          require 'new_relic/agent/continuous_profiling/profile_encoder'
          bytes = ProfileEncoder.encode(report)
          @exporter.export(bytes)
        end
      end
    end
  end
end
