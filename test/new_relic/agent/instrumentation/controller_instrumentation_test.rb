require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
class NewRelic::Agent::Instrumentation::ControllerInstrumentationTest < Test::Unit::TestCase
  require 'new_relic/agent/instrumentation/controller_instrumentation'
  class TestObject
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
  end

  def test_detect_upstream_wait_basic
    start_time = Time.now
    object = TestObject.new
    # should return the start time above by default
    object.expects(:newrelic_request_headers).returns({:request => 'headers'}).twice
    object.expects(:parse_frontend_headers).with({:request => 'headers'}).returns(1.0)
    assert_equal(start_time, object.send(:_detect_upstream_wait, start_time))
    assert_equal(1.0, Thread.current[:queue_time])
  end
  
  def test_detect_upstream_wait_with_upstream
    # should return the start time from the headers for use in the
    # apdex calculation
    raise 'should test this case'
  end

  def test_detect_upstream_wait_swallows_errors
    start_time = Time.now
    object = TestObject.new
    Thread.current[:queue_time] = nil
    # should return the start time above when an error is raised
    object.expects(:newrelic_request_headers).returns({:request => 'headers'}).twice
    object.expects(:parse_frontend_headers).with({:request => 'headers'}).raises("an error")
    assert_equal(start_time, object.send(:_detect_upstream_wait, start_time))
  end
end
