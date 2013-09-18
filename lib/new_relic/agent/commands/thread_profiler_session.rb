# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/threading/thread_profile'

module NewRelic
  module Agent
    module Commands

      class ThreadProfilerSession

        def initialize(thread_profiling_service)
          @thread_profiling_service = thread_profiling_service
        end

        def self.is_supported?
          RUBY_VERSION >= "1.9.2"
        end

        def handle_start_command(agent_command)
          raise_unsupported_error unless self.class.is_supported?
          raise_already_started_error if running?
          start(agent_command)
        end

        def handle_stop_command(agent_command)
          report_data = agent_command.arguments.fetch("report_data", true)
          stop(report_data)
        end

        def start(agent_command)
          profile = @thread_profiling_service.subscribe(
            NewRelic::Agent::Threading::ThreadProfilingService::ALL_TRANSACTIONS,
            agent_command.arguments
          )

          @started_at = Time.now
          @duration = profile.duration
        end

        def stop(report_data)
          return unless running?
          NewRelic::Agent.logger.debug("Stopping thread profile.")
          @finished_profile = @thread_profiling_service.harvest(NewRelic::Agent::Threading::ThreadProfilingService::ALL_TRANSACTIONS)
          @thread_profiling_service.unsubscribe(NewRelic::Agent::Threading::ThreadProfilingService::ALL_TRANSACTIONS)
          @finished_profile = nil if !report_data
        end

        def harvest
          profile = @finished_profile
          @thread_profiling_service.profile_agent_code = false
          @finished_profile = nil
          profile
        end

        def running?
          @thread_profiling_service.subscribed?(NewRelic::Agent::Threading::ThreadProfilingService::ALL_TRANSACTIONS)
        end

        def finished?
          @started_at && (Time.now > @started_at + @duration) || stopped?
        end

        def stopped?
          !!@finished_profile
        end

        private

        def raise_command_error(msg)
          NewRelic::Agent.logger.debug(msg)
          raise NewRelic::Agent::Commands::AgentCommandRouter::AgentCommandError.new(msg)
        end

        def raise_already_started_error
          msg = "Profile already in progress. Ignoring agent command to start another."
          raise_command_error(msg)
        end

        def raise_unsupported_error
          msg = <<-EOF
Thread profiling is only supported on 1.9.2 and greater versions of Ruby.
We detected running agents capable of profiling, but the profile started with
an agent running Ruby #{RUBY_VERSION}.

Profiling again might select an appropriate agent, but we recommend running a
consistent version of Ruby across your application for better results.
          EOF
          raise_command_error(msg)
        end

      end
    end
  end
end
