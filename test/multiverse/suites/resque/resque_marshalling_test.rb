# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

class ResqueMarshallingTest < Minitest::Test

  include MultiverseHelpers
  include MarshallingTestCases

  setup_and_teardown_agent

  class DummyJob
    extend Resque::Plugins::NewRelicInstrumentation
  end

  def invoke_hook(name)
    hooks = Array(Resque.send(name))
    hooks.each { |h| h.call }
  end

  def around_each
    invoke_hook(:before_first_fork)
    invoke_hook(:before_fork)

    child_pid = Process.fork

    if child_pid
      Process.wait(child_pid)
    else
      invoke_hook(:after_fork)
      DummyJob.around_perform_with_monitoring do
        yield
      end
      exit
    end
  end

  def after_each
    NewRelic::Agent::PipeChannelManager.listener.stop
  end
end
