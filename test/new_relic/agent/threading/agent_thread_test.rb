# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/threading/agent_thread'

module NewRelic::Agent::Threading
  class AgentThreadTest < Minitest::Test

    def test_sets_label
      t = AgentThread.create("labelled") {}
      assert_equal "labelled", t[:newrelic_label]
      t.join
    end

    def test_bucket_thread_as_agent_when_profiling
      t = AgentThread.create("labelled") {}
      assert_equal :agent, AgentThread.bucket_thread(t, true)
      t.join
    end

    def test_bucket_thread_as_agent_when_not_profiling
      t = AgentThread.create("labelled") {}
      assert_equal :ignore, AgentThread.bucket_thread(t, false)
      t.join
    end

    def test_bucket_thread_as_request
      q0 = Queue.new
      q1 = Queue.new

      t = Thread.new do
        begin
          in_web_transaction do
            q0.push 'unblock main thread'
            q1.pop
          end
        rescue => e
          q0.push 'unblock main thread'
          fail e
        end
      end

      q0.pop # wait until thread has had a chance to start up
      assert_equal :request, AgentThread.bucket_thread(t, DONT_CARE)

      q1.push 'unblock background thread'
      t.join
    end

    def test_bucket_thread_as_background
      q0 = Queue.new
      q1 = Queue.new

      t = ::Thread.new do
        begin
          in_transaction do
            q0.push 'unblock main thread'
            q1.pop
          end
        rescue => e
          q0.push 'unblock main thread'
          fail e
        end
      end

      q0.pop # wait until thread pushes to q
      assert_equal :background, AgentThread.bucket_thread(t, DONT_CARE)

      q1.push 'unblock background thread'
      t.join
    end

    def test_bucket_thread_as_other
      t = ::Thread.new {}
      assert_equal :other, AgentThread.bucket_thread(t, DONT_CARE)
      t.join
    end

    def test_runs_block
      called = false

      t = AgentThread.create("labelled") { called = true }
      t.join

      assert called
    end

    def test_standard_error_is_caught
      expects_logging(:error, includes("exited"), any_parameters)

      t = AgentThread.create("fail") { raise "O_o" }
      t.join

      assert_thread_completed(t)
    end

    def test_exception_is_reraised
      expects_logging(:error, includes("exited"), any_parameters)

      assert_raises(Exception) do
        begin
          t = AgentThread.create("fail") { raise Exception.new }
          t.join
        ensure
          assert_thread_died_from_exception(t)
        end
      end
    end

    def assert_thread_completed(t)
      assert_equal false, t.status
    end

    def assert_thread_died_from_exception(t)
      assert_equal nil, t.status
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
      AgentThread.scrub_backtrace(dummy_thread, true)
    end

    def test_scrub_backtrace_handles_nil_backtrace
      bt = AgentThread.scrub_backtrace(stub(:backtrace => nil), false)
      assert_nil(bt)
    end

    DONT_CARE = true
  end
end
