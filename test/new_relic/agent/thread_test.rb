require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/thread'

class ThreadTest < Test::Unit::TestCase

  def test_sets_label
    t = NewRelic::Agent::Thread.new("labelled") {}
    assert_equal "labelled", t[:newrelic_label]
  end

  def test_bucket_thread_as_agent_when_profiling
    t = NewRelic::Agent::Thread.new("labelled") {}
    assert_equal :agent, NewRelic::Agent::Thread.bucket_thread(t, true)
  end

  def test_bucket_thread_as_agent_when_not_profiling
    t = NewRelic::Agent::Thread.new("labelled") {}
    assert_equal :ignore, NewRelic::Agent::Thread.bucket_thread(t, false)
  end

  def test_bucket_thread_as_request
    t = ::Thread.new {}
    frame = NewRelic::Agent::Instrumentation::MetricFrame.new
    frame.request = "has a request"
    t[:newrelic_metric_frame] = frame

    assert_equal :request, NewRelic::Agent::Thread.bucket_thread(t, DONT_CARE)
  end

  def test_bucket_thread_as_background
    t = ::Thread.new {}
    frame = NewRelic::Agent::Instrumentation::MetricFrame.new
    t[:newrelic_metric_frame] = frame

    assert_equal :background, NewRelic::Agent::Thread.bucket_thread(t, DONT_CARE)
  end

  def test_bucket_thread_as_other
    t = ::Thread.new {}
    assert_equal :other, NewRelic::Agent::Thread.bucket_thread(t, DONT_CARE)
  end

  def test_runs_block
    called = false

    t = NewRelic::Agent::Thread.new("labelled") { called = true }
    t.join

    assert called
  end

  DONT_CARE = true
end
