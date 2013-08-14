# encoding: utf-8
#k This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/threading/thread_profile'

module NewRelic
  module Agent

    class ThreadProfiler

      def self.is_supported?
        RUBY_VERSION >= "1.9.2"
      end

      def handle_start_command(options)
        unsupported?
        start_unless_running_and_notify(options)
      end

      def handle_stop_command(options)
        unsupported?
        stop_and_notify(options)
      end

      def start(profile_id, duration, interval, profile_agent_code)
        if !ThreadProfiler.is_supported?
          NewRelic::Agent.logger.debug("Not starting thread profile as it isn't supported on this environment")
          @profile = nil
        else
          NewRelic::Agent.logger.debug("Starting thread profile. profile_id=#{profile_id}, duration=#{duration}")
          @profile = Threading::ThreadProfile.new(profile_id, duration, interval, profile_agent_code)
          @profile.run
        end
      end

      def stop(report_data)
        @profile.stop unless @profile.nil?
        @profile = nil if !report_data
      end

      def harvest
        profile = @profile
        @profile = nil
        profile
      end

      def running?
        !@profile.nil?
      end

      def finished?
        @profile && @profile.finished?
      end

      private

      def start_unless_running_and_notify(arguments)
        profile_id = arguments.fetch("profile_id", -1)
        duration =   arguments.fetch("duration", 120)
        interval =   arguments.fetch("sample_period", 0.1)
        profile_agent_code = arguments.fetch("profile_agent_code", true)

        if running?
          msg = "Profile already in progress. Ignoring agent command to start another."
          NewRelic::Agent.logger.debug(msg)
          raise NewRelic::Agent::AgentCommandRouter::AgentCommandError.new(msg)
        else
          start(profile_id, duration, interval, profile_agent_code)
        end
      end

      def stop_and_notify(arguments)
        report_data = arguments.fetch("report_data", true)
        stop(report_data)
        yield(command_id) if block_given?
      end

      def unsupported?
        return false if ThreadProfiler.is_supported?

        msg = <<-EOF
Thread profiling is only supported on 1.9.2 and greater versions of Ruby.
We detected running agents capable of profiling, but the profile started with
an agent running Ruby #{RUBY_VERSION}.

Profiling again might select an appropriate agent, but we recommend running a
consistent version of Ruby across your application for better results.
EOF
        NewRelic::Agent.logger.debug(msg)
        raise NewRelic::Agent::AgentCommandRouter::AgentCommandError.new(msg)
        true
      end

    end

  end
end
