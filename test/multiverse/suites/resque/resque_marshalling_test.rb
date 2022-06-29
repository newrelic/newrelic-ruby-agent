# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

if NewRelic::LanguageSupport.can_fork?

  class ResqueMarshallingTest < Minitest::Test
    include MultiverseHelpers
    include MarshallingTestCases

    setup_and_teardown_agent

    def invoke_hook(name, *args)
      hooks = Array(Resque.send(name))
      hooks.each { |h| h.call(*args) }
    end

    def around_each
      invoke_hook(:before_first_fork)

      # We just need something that responds to object_id here, because our
      # Resque instrumentation uses that to assign a unique identifier to the pipe
      # that will be used to send data about this job.
      job = Object.new

      invoke_hook(:before_fork, job)

      child_pid = Process.fork

      if child_pid
        Process.wait(child_pid)
      else
        invoke_hook(:after_fork, job)
        yield

        run_harvest
        exit
      end
    end

    def after_each
      NewRelic::Agent::PipeChannelManager.listener.stop
    end
  end

end
