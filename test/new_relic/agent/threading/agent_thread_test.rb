# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/threading/agent_thread'

module NewRelic::Agent::Threading
  class AgentThreadTest < Test::Unit::TestCase

    def test_sets_label
      t = AgentThread.new("labelled") {}
      assert_equal "labelled", t[:newrelic_label]
    end

    def test_bucket_thread_as_agent_when_profiling
      t = AgentThread.new("labelled") {}
      assert_equal :agent, AgentThread.bucket_thread(t, true)
    end

    def test_bucket_thread_as_agent_when_not_profiling
      t = AgentThread.new("labelled") {}
      assert_equal :ignore, AgentThread.bucket_thread(t, false)
    end

    def test_bucket_thread_as_request
      t = ::Thread.new {
        txn = NewRelic::Agent::Transaction.new
        txn.request = "has a request"

        NewRelic::Agent::TransactionState.get.current_transaction_stack = [txn]
      }.join

      assert_equal :request, AgentThread.bucket_thread(t, DONT_CARE)
    end

    def test_bucket_thread_as_background
      t = ::Thread.new {
        txn = NewRelic::Agent::Transaction.new
        NewRelic::Agent::TransactionState.get.current_transaction_stack = [txn]
      }.join

      assert_equal :background, AgentThread.bucket_thread(t, DONT_CARE)
    end

    def test_bucket_thread_as_other_empty_txn_stack
      t = ::Thread.new {
        NewRelic::Agent::TransactionState.get.current_transaction_stack = []
      }.join

      assert_equal :other, AgentThread.bucket_thread(t, DONT_CARE)
    end

    def test_bucket_thread_as_other_no_txn_stack
      t = ::Thread.new {
        NewRelic::Agent::TransactionState.get.current_transaction_stack = nil
      }.join

      assert_equal :other, AgentThread.bucket_thread(t, DONT_CARE)
    end

    def test_bucket_thread_as_other
      t = ::Thread.new {}
      assert_equal :other, AgentThread.bucket_thread(t, DONT_CARE)
    end

    def test_runs_block
      called = false

      t = AgentThread.new("labelled") { called = true }
      t.join

      assert called
    end

    TRACE = [
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/gems/1.9.1/gems/eventmachine-0.12.10/lib/eventmachine.rb:100:in `catch'",
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/gems/1.9.1/gems/newrelic_rpm-3.5.3.452.dev/lib/new_relic/agent/agent.rb:200:in `start_worker_thread'",
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/gems/1.9.1/gems/thin-1.5.0/lib/thin/backends/base.rb:300:in `block (3 levels) in run'",
    ]

    def test_scrubs_backtrace_when_not_profiling_agent_code
      result = AgentThread.scrub_backtrace(stub(:backtrace => TRACE.dup), false)
      assert_equal [TRACE[0], TRACE[2]], result
    end

    def test_doesnt_scrub_backtrace_when_profiling_agent_code
      result = AgentThread.scrub_backtrace(stub(:backtrace => TRACE.dup), true)
      assert_equal TRACE, result
    end

    def test_scrub_backtrace_handles_errors_during_backtrace
      dummy_thread = stub
      dummy_thread.stubs(:backtrace).raises(StandardError.new('nah'))
      assert_nothing_raised do
        AgentThread.scrub_backtrace(dummy_thread, true)
      end
    end

    def test_scrub_backtrace_handles_nil_backtrace
      bt = AgentThread.scrub_backtrace(stub(:backtrace => nil), false)
      assert_nil(bt)
    end

    DONT_CARE = true
  end
end
