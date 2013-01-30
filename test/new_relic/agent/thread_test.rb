require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/thread'

class ThreadTest < Test::Unit::TestCase

  def test_sets_label
    t = NewRelic::Agent::AgentThread.new("labelled") {}
    assert_equal "labelled", t[:newrelic_label]
  end

  def test_bucket_thread_as_agent_when_profiling
    t = NewRelic::Agent::AgentThread.new("labelled") {}
    assert_equal :agent, NewRelic::Agent::AgentThread.bucket_thread(t, true)
  end

  def test_bucket_thread_as_agent_when_not_profiling
    t = NewRelic::Agent::AgentThread.new("labelled") {}
    assert_equal :ignore, NewRelic::Agent::AgentThread.bucket_thread(t, false)
  end

  def test_bucket_thread_as_request
    t = ::Thread.new {}
    frame = NewRelic::Agent::Instrumentation::MetricFrame.new
    frame.request = "has a request"
    t[:newrelic_metric_frame] = frame

    assert_equal :request, NewRelic::Agent::AgentThread.bucket_thread(t, DONT_CARE)
  end

  def test_bucket_thread_as_background
    t = ::Thread.new {}
    frame = NewRelic::Agent::Instrumentation::MetricFrame.new
    t[:newrelic_metric_frame] = frame

    assert_equal :background, NewRelic::Agent::AgentThread.bucket_thread(t, DONT_CARE)
  end

  def test_bucket_thread_as_other_if_nil_frame
    t = ::Thread.new {}
    t[:newrelic_metric_frame] = nil

    assert_equal :other, NewRelic::Agent::AgentThread.bucket_thread(t, DONT_CARE)
  end

  def test_bucket_thread_as_other
    t = ::Thread.new {}
    assert_equal :other, NewRelic::Agent::AgentThread.bucket_thread(t, DONT_CARE)
  end

  def test_runs_block
    called = false

    t = NewRelic::Agent::AgentThread.new("labelled") { called = true }
    t.join

    assert called
  end

  TRACE = [
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/gems/1.9.1/gems/eventmachine-0.12.10/lib/eventmachine.rb:100:in `catch'",
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/gems/1.9.1/gems/newrelic_rpm-3.5.3.452.dev/lib/new_relic/agent/agent.rb:200:in `start_worker_thread'",
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/gems/1.9.1/gems/thin-1.5.0/lib/thin/backends/base.rb:300:in `block (3 levels) in run'",
    ]

  def test_scrubs_backtrace_when_not_profiling_agent_code
    result = NewRelic::Agent::AgentThread.scrub_backtrace(stub(:backtrace => TRACE), false)
    assert_equal [TRACE[0], TRACE[2]], result
  end

  def test_doesnt_scrub_backtrace_when_profiling_agent_code
    result = NewRelic::Agent::AgentThread.scrub_backtrace(stub(:backtrace => TRACE), true)
    assert_equal TRACE, result
  end

  def test_scrub_backtrace_handles_errors_during_backtrace
    dummy_thread = stub
    dummy_thread.stubs(:backtrace).raises(StandardError.new('nah'))
    assert_nothing_raised do
      NewRelic::Agent::AgentThread.scrub_backtrace(dummy_thread, true)
    end
  end

  def test_scrub_backtrace_handles_nil_backtrace
    bt = NewRelic::Agent::AgentThread.scrub_backtrace(stub(:backtrace => nil), false)
    assert_nil(bt)
  end

  DONT_CARE = true
end
