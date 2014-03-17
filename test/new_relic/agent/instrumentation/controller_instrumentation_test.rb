# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
class NewRelic::Agent::Instrumentation::ControllerInstrumentationTest < Minitest::Test
  require 'new_relic/agent/instrumentation/controller_instrumentation'
  class TestObject
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def public_transaction(*args); end

    protected
    def protected_transaction(*args); end

    private
    def private_transaction(*args); end

    add_transaction_tracer :public_transaction
    add_transaction_tracer :protected_transaction
    add_transaction_tracer :private_transaction
  end

  def setup
    @object = TestObject.new
    @dummy_headers = { :request => 'headers' }
    @txn_namer = NewRelic::Agent::Instrumentation:: \
      ControllerInstrumentation::TransactionNamer.new(@object)
  end

  def test_detect_upstream_wait_returns_transaction_start_time_if_nothing_from_headers
    @object.stubs(:newrelic_request_headers).returns(@dummy_headers)
    in_transaction do |txn|
      NewRelic::Agent::Instrumentation::QueueTime.expects(:parse_frontend_timestamp) \
        .with(@dummy_headers, txn.start_time).returns(txn.start_time)
      assert_equal(txn.start_time, @object.send(:_detect_upstream_wait, txn))
    end
  end

  def test_detect_upstream_wait_returns_parsed_timestamp_from_headers
    @object.stubs(:newrelic_request_headers).returns(@dummy_headers)
    in_transaction do |txn|
      earlier_time = txn.start_time - 1
      NewRelic::Agent::Instrumentation::QueueTime.expects(:parse_frontend_timestamp) \
        .with(@dummy_headers, txn.start_time).returns(earlier_time)
      assert_equal(earlier_time, @object.send(:_detect_upstream_wait, txn))
    end
  end

  def test_detect_upstream_wait_swallows_errors
    @object.stubs(:newrelic_request_headers).returns(@dummy_headers)
    in_transaction do |txn|
      NewRelic::Agent::Instrumentation::QueueTime.expects(:parse_frontend_timestamp) \
        .with(@dummy_headers, txn.start_time).raises("an error")
      assert_equal(txn.start_time, @object.send(:_detect_upstream_wait, txn))
    end
  end

  def test_detect_upsteam_wait_does_not_parse_timestamp_in_nested_transaction
    @object.stubs(:newrelic_request_headers).returns(@dummy_headers)
    in_transaction do |outer|
      in_transaction do |inner|
        NewRelic::Agent::Instrumentation::QueueTime.expects(:parse_frontend_timestamp).never
        assert_equal(inner.start_time, @object.send(:_detect_upstream_wait, inner))
      end
    end
  end

  def test_transaction_name_calls_newrelic_metric_path
    @object.stubs(:newrelic_metric_path).returns('some/wacky/path')
    assert_equal('Controller/some/wacky/path', @txn_namer.name)
  end

  def test_transaction_name_applies_category_and_path
    assert_equal('Controller/metric/path',
                 @txn_namer.name(:category => :controller,
                                 :path => 'metric/path'))
    assert_equal('OtherTransaction/Background/metric/path',
                 @txn_namer.name(:category => :task,
                                 :path => 'metric/path'))
    assert_equal('Controller/Rack/metric/path',
                 @txn_namer.name(:category => :rack,
                                 :path => 'metric/path'))
    assert_equal('Controller/metric/path',
                 @txn_namer.name(:category => :uri,
                                 :path => 'metric/path'))
    assert_equal('Controller/Sinatra/metric/path',
                 @txn_namer.name(:category => :sinatra,
                                 :path => 'metric/path'))
    assert_equal('Blarg/metric/path',
                 @txn_namer.name(:category => 'Blarg',
                                 :path => 'metric/path'))
  end

  def test_transaction_name_uses_class_name_if_path_not_specified
    assert_equal('Controller/NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject',
                 @txn_namer.name(:category => :controller))
  end

  def test_transaction_name_applies_action_name_if_specified_and_not_path
    assert_equal('Controller/NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject/action',
                 @txn_namer.name(:category => :controller,
                                 :name => 'action'))
  end

  def test_transaction_path_name
    result = @txn_namer.path_name
    assert_equal("NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject", result)
  end

  def test_transaction_path_name_with_name
    result = @txn_namer.path_name(:name => "test")
    assert_equal("NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject/test", result)
  end

  def test_transaction_path_name_with_overridden_class_name
    result = @txn_namer.path_name(:name => "perform", :class_name => 'Resque')
    assert_equal("Resque/perform", result)
  end

  def test_add_transaction_tracer_should_not_double_instrument
    TestObject.expects(:alias_method).never
    TestObject.class_eval do
      add_transaction_tracer :public_transaction
      add_transaction_tracer :protected_transaction
      add_transaction_tracer :private_transaction
    end
    obj = TestObject.new
  end
end
