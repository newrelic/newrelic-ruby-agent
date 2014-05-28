# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/threading/fake_thread'

module ThreadedTestCase
  def setup_fake_threads
    @original_thread_class = NewRelic::Agent::Threading::AgentThread.backing_thread_class
    NewRelic::Agent::Threading::AgentThread.backing_thread_class = FakeThread
    FakeThread.list.clear
  end

  def teardown_fake_threads
    NewRelic::Agent::Threading::AgentThread.backing_thread_class = @original_thread_class
    FakeThread.list.clear
  end
end
