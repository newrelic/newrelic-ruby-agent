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
    NewRelic::Agent.drop_buffered_data
    @object = TestObject.new
    @dummy_headers = { :request => 'headers' }
    @txn_namer = NewRelic::Agent::Instrumentation:: \
      ControllerInstrumentation::TransactionNamer.new(@object)
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def test_apdex_recorded
    @object.public_transaction
    assert_metrics_recorded("Apdex")
  end

  def test_apdex_ignored
    @object.stubs(:ignore_apdex?).returns(true)
    @object.public_transaction
    assert_metrics_not_recorded("Apdex")
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

  def test_add_transaction_tracer_defines_with_method
    assert TestObject.method_defined? :public_transaction_with_newrelic_transaction_trace
  end

  def test_add_transaction_tracer_defines_without_method
    assert TestObject.method_defined? :public_transaction_without_newrelic_transaction_trace
  end

  def test_parse_punctuation
    ['?', '!', '='].each do |punctuation_mark|
      result = TestObject.parse_punctuation("foo#{punctuation_mark}")
      assert_equal ['foo', punctuation_mark], result
    end
  end

  def test_argument_list
    options = {:foo => :bar, :params => '{ :account_name => args[0].name }', :far => 7}
    result = TestObject.generate_argument_list(options)
    expected = [":far => \"7\"", ":foo => :bar", ":params => { :account_name => args[0].name }"]
    assert_equal expected.sort, result.sort
  end

  def test_build_method_names
    result = TestObject.build_method_names('foo', '?')
    expected = ["foo_with_newrelic_transaction_trace?", "foo_without_newrelic_transaction_trace?"]
    assert_equal expected, result
  end

  def test_already_added_transaction_tracer_returns_true_if_with_method_defined
    with_method_name = 'public_transaction_with_newrelic_transaction_trace'
    assert TestObject.already_added_transaction_tracer?(TestObject, with_method_name)
  end
end
