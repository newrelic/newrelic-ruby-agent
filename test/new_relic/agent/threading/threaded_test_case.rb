# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/threading/fake_thread'

class ThreadedTestCase < Test::Unit::TestCase
  def setup
    @original_thread_class = NewRelic::Agent::Threading::AgentThread
    swap_thread_class(FakeThread)
  end

  def teardown
    swap_thread_class(@original_thread_class)
    @original_thread_class = nil

    FakeThread.list.clear
  end

  def default_test
    # no-op to keep quiet....
  end

  private

  def swap_thread_class(klass)
    if NewRelic::Agent::Threading.const_defined?("AgentThread")
      NewRelic::Agent::Threading.send(:remove_const, "AgentThread")
    end
    NewRelic::Agent::Threading.const_set("AgentThread", klass)
  end
end

