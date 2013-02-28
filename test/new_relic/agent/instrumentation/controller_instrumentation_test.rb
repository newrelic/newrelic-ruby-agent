# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
class NewRelic::Agent::Instrumentation::ControllerInstrumentationTest < Test::Unit::TestCase
  require 'new_relic/agent/instrumentation/controller_instrumentation'
  class TestObject
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
  end

  def setup
    @object = TestObject.new
  end

  def test_detect_upstream_wait_basic
    start_time = Time.now
    # should return the start time above by default
    @object.expects(:newrelic_request_headers).returns({:request => 'headers'}).twice
    NewRelic::Agent::Instrumentation::QueueTime.expects(:parse_frontend_timestamp) \
      .with({:request => 'headers'}, start_time).returns(start_time)
    assert_equal(start_time, @object.send(:_detect_upstream_wait, start_time))
  end

  def test_detect_upstream_wait_with_upstream
    start_time = Time.now
    runs_at = start_time + 1
    @object = TestObject.new
    @object.expects(:newrelic_request_headers).returns(true).twice
    NewRelic::Agent::Instrumentation::QueueTime.expects(:parse_frontend_timestamp) \
      .with(true, runs_at).returns(start_time)
    assert_equal(start_time, @object.send(:_detect_upstream_wait, runs_at))
  end

  def test_detect_upstream_wait_swallows_errors
    start_time = Time.now
    # should return the start time above when an error is raised
    @object.expects(:newrelic_request_headers).returns({:request => 'headers'}).twice
    NewRelic::Agent::Instrumentation::QueueTime.expects(:parse_frontend_timestamp) \
      .with({:request => 'headers'}, start_time).raises("an error")
    assert_equal(start_time, @object.send(:_detect_upstream_wait, start_time))
  end

  def test_transaction_name_calls_newrelic_metric_path
    @object.stubs(:newrelic_metric_path).returns('some/wacky/path')
    assert_equal('Controller/some/wacky/path', @object.send(:transaction_name))
  end

  def test_transaction_name_applies_category_and_path
    assert_equal('Controller/metric/path',
                 @object.send(:transaction_name,
                              :category => :controller,
                              :path => 'metric/path'))
    assert_equal('OtherTransaction/Background/metric/path',
                 @object.send(:transaction_name,
                              :category => :task, :path => 'metric/path'))
    assert_equal('Controller/Rack/metric/path',
                 @object.send(:transaction_name,
                              :category => :rack, :path => 'metric/path'))
    assert_equal('Controller/metric/path',
                 @object.send(:transaction_name,
                              :category => :uri, :path => 'metric/path'))
    assert_equal('Controller/Sinatra/metric/path',
                 @object.send(:transaction_name,
                              :category => :sinatra,
                              :path => 'metric/path'))
    assert_equal('Blarg/metric/path',
                 @object.send(:transaction_name,
                              :category => 'Blarg', :path => 'metric/path'))

  end

  def test_transaction_name_uses_class_name_if_path_not_specified
    assert_equal('Controller/NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject',
                 @object.send(:transaction_name, :category => :controller))
  end

  def test_transaction_name_applies_action_name_if_specified_and_not_path
    assert_equal('Controller/NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject/action',
                 @object.send(:transaction_name, :category => :controller,
                              :name => 'action'))
  end

  def test_transaction_name_applies_name_rules
    rule = NewRelic::Agent::RulesEngine::Rule.new('match_expression' => '[0-9]+',
                                                  'replacement'      => '*',
                                                  'replace_all'      => true)
    NewRelic::Agent.instance.transaction_rules << rule
    assert_equal('foo/*/bar/*',
                 @object.send(:transaction_name, :category => 'foo',
                              :path => '1/bar/22'))
  ensure
    NewRelic::Agent.instance.instance_variable_set(:@transaction_rules,
                                              NewRelic::Agent::RulesEngine.new)
  end

  def test_path_class_and_action
    result = @object.send(:path_class_and_action, {})
    assert_equal("NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject", result)
  end

  def test_path_class_and_action_with_name
    result = @object.send(:path_class_and_action, :name => "test")
    assert_equal("NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject/test", result)
  end

  def test_path_class_and_action_with_overridden_class_name
    result = @object.send(:path_class_and_action, :name => "perform", :class_name => 'Resque')
    assert_equal("Resque/perform", result)
  end
end
