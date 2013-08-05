# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/threading/agent_thread'
require 'new_relic/agent/threading/thread_profile'

module NewRelic
  module Agent

    class ThreadProfiler

      attr_reader :profile

      def self.is_supported?
        RUBY_VERSION >= "1.9.2"
      end

      def start(profile_id, duration, interval, profile_agent_code)
        if !ThreadProfiler.is_supported?
          ::NewRelic::Agent.logger.debug("Not starting thread profile as it isn't supported on this environment")
          @profile = nil
        else
          ::NewRelic::Agent.logger.debug("Starting thread profile. profile_id=#{profile_id}, duration=#{duration}")
          @profile = NewRelic::Agent::Threading::ThreadProfile.new(profile_id, duration, interval, profile_agent_code)
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

      def unsupported?(command_id, &results_callback)
        return false if ThreadProfiler.is_supported?

        msg = <<-EOF
Thread profiling is only supported on 1.9.2 and greater versions of Ruby.
We detected running agents capable of profiling, but the profile started with
an agent running Ruby #{RUBY_VERSION}.

Profiling again might select an appropriate agent, but we recommend running a
consistent version of Ruby across your application for better results.
EOF
        NewRelic::Agent.logger.debug(msg)
        results_callback.call(command_id, msg) if !results_callback.nil?
        true
      end

      def respond_to_start(command_id, name, arguments, &results_callback)
        return if unsupported?(command_id, &results_callback)
        start_unless_running_and_notify(command_id, arguments, &results_callback)
      end

      def respond_to_stop(command_id, name, arguments, &results_callback)
        return if unsupported?(command_id, &results_callback)
        stop_and_notify(command_id, arguments, &results_callback)
      end

      def running?
        !@profile.nil?
      end

      def finished?
        @profile && @profile.finished?
      end

      private

      def start_unless_running_and_notify(command_id, arguments)
        profile_id = arguments.fetch("profile_id", -1)
        duration =   arguments.fetch("duration", 120)
        interval =   arguments.fetch("sample_period", 0.1)
        profile_agent_code = arguments.fetch("profile_agent_code", true)

        if running?
          msg = "Profile already in progress. Ignoring agent command to start another."
          ::NewRelic::Agent.logger.debug(msg)
          yield(command_id, msg) if block_given?
        else
          start(profile_id, duration, interval, profile_agent_code)
          yield(command_id) if block_given?
        end
      end

      def stop_and_notify(command_id, arguments)
        report_data = arguments.fetch("report_data", true)
        stop(report_data)
        yield(command_id) if block_given?
      end

    end

  end
end
