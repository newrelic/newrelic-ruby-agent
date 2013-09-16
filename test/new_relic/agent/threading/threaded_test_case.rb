# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/threading/fake_thread'

module ThreadedTestCase
  def setup_fake_threads
    @original_thread_class = NewRelic::Agent::Threading::AgentThread
    swap_thread_class(FakeThread)
  end

  def teardown_fake_threads
    swap_thread_class(@original_thread_class)
    @original_thread_class = nil

    FakeThread.list.clear
  end

  private

  def swap_thread_class(klass)
    if NewRelic::Agent::Threading.const_defined?("AgentThread")
      NewRelic::Agent::Threading.send(:remove_const, "AgentThread")
    end
    NewRelic::Agent::Threading.const_set("AgentThread", klass)
  end
end
