# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'

class Insider
  def initialize(stats_engine)
    @stats_engine = stats_engine
  end

  def catcher(level = 0)
    thrower(level) if level > 0
  end

  def thrower(level)
    if level == 0
      # don't use a real sampler because we can't instantiate one
      # NewRelic::Agent::TransactionSampler.new(NewRelic::Agent.instance)
      begin
        fail "This should not have worked."
      rescue
      end
    else
      thrower(level - 1)
    end
  end
end

module NewRelic
  module Agent
    extend self
    def module_method_to_be_traced(x, testcase)
      testcase.assert_equal 'x', x
    end
  end
end

module TestModuleWithLog
  class << self
    def other_method
      # just here to be traced
      log "12345"
    end

    def log(msg)
      msg
    end

    include NewRelic::Agent::MethodTracer
    add_method_tracer :other_method, 'Custom/foo/bar'
  end
end

with_config(:'code_level_metrics.enabled' => true) do
  class MyClass
    def self.class_method
    end

    class << self
      include NewRelic::Agent::MethodTracer
      add_method_tracer :class_method
    end
  end

  module MyModule
    def self.module_method
    end

    class << self
      include NewRelic::Agent::MethodTracer
      add_method_tracer :module_method
    end
  end
end

class MyProxyClass < BasicObject
  include ::NewRelic::Agent::MethodTracer

  def hello
    "hello"
  end

  add_method_tracer :hello, 'Custom/proxy/hello'
end

class NewRelic::Agent::MethodTracerTest < Minitest::Test
  attr_reader :stats_engine

  def setup
    NewRelic::Agent::Tracer.clear_state

    NewRelic::Agent.manual_start
    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.clear_stats
    @metric_name ||= nil

    nr_freeze_process_time

    super
  end

  def teardown
    @stats_engine.clear_stats

    self.class._nr_clear_traced_methods!

    @metric_name = nil
    NewRelic::Agent.shutdown
    super
  end

  def test_preserve_logging
    assert_equal '12345', TestModuleWithLog.other_method
  end

  def test_trace_execution_scoped_records_metric_data
    metric = "hello"

    in_transaction do
      self.class.trace_execution_scoped(metric) do
        advance_process_time 0.05
      end
    end

    assert_metrics_recorded metric => {:call_count => 1, :total_call_time => 0.05}
  end

  def test_trace_execution_scoped_with_no_metrics_skips_out
    self.class.trace_execution_scoped([]) do
      advance_process_time 0.05
    end

    assert_metrics_recorded_exclusive(['Supportability/API/trace_execution_scoped'])
  end

  def test_trace_execution_scoped_pushes_transaction_scope
    in_transaction do
      self.class.trace_execution_scoped('yeap') do
        'ptoo'
      end
    end
    assert_metrics_recorded 'yeap' => {:call_count => 1}
  end

  METRIC = "metric"

  def test_add_method_tracer
    @metric_name = METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC
    in_transaction do
      method_to_be_traced 1, 2, 3, true, METRIC
    end

    begin
      self.class.remove_method_tracer :method_to_be_traced
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end

    assert_metrics_recorded METRIC => {:call_count => 1, :total_call_time => 0.05}
  end

  def test_add_method_tracer__default
    self.class.add_method_tracer :simple_method

    in_transaction do
      simple_method
    end

    metric = "Custom/#{self.class.name}/simple_method"
    assert_metrics_recorded metric => {:call_count => 1}
  end

  def test_add_class_method_tracer
    in_transaction do
      MyClass.class_method
    end

    metric = "Custom/MyClass/Class/class_method"
    assert_metrics_recorded metric => {:call_count => 1}
  end

  def test_code_level_metrics_for_a_class_method
    in_transaction do |txn|
      MyClass.class_method

      attributes = txn.segments.last.code_attributes
      assert_equal __FILE__, attributes['code.filepath']
      assert_equal 'self.class_method', attributes['code.function']
      assert_equal 57, attributes['code.lineno']
      assert_equal 'MyClass', attributes['code.namespace']
    end
  end

  def test_add_module_method_tracer
    in_transaction do
      MyModule.module_method
    end

    metric = "Custom/MyModule/Class/module_method"
    assert_metrics_recorded metric => {:call_count => 1}
  end

  def test_code_level_metrics_for_a_module_method
    in_transaction do |txn|
      MyModule.module_method

      attributes = txn.segments.last.code_attributes
      assert_equal __FILE__, attributes['code.filepath']
      assert_equal 'self.module_method', attributes['code.function']
      assert_equal 67, attributes['code.lineno']
      assert_equal 'MyModule', attributes['code.namespace']
    end
  end

  def anonymous_class
    with_config(:'code_level_metrics.enabled' => true) do
      Class.new do
        def instance_method; end
        include NewRelic::Agent::MethodTracer
        add_method_tracer :instance_method
      end
    end
  end

  def test_add_anonymous_class_method_tracer
    cls = anonymous_class

    in_transaction do
      cls.new.instance_method
    end

    metric = "Custom/AnonymousClass/instance_method"
    assert_metrics_recorded metric => {:call_count => 1}
  end

  def test_code_level_metrics_for_an_anonymous_method
    cls = anonymous_class

    in_transaction do |txn|
      cls.new.instance_method

      attributes = txn.segments.last.code_attributes
      assert_equal __FILE__, attributes['code.filepath']
      assert_equal 'instance_method', attributes['code.function']
      assert_equal 220, attributes['code.lineno']
      assert_equal '(Anonymous)', attributes['code.namespace']
    end
  end

  def test_add_method_tracer__reentry
    self.class.add_method_tracer :simple_method
    self.class.add_method_tracer :simple_method
    self.class.add_method_tracer :simple_method

    in_transaction do
      simple_method
    end

    metric = "Custom/#{self.class.name}/simple_method"
    assert_metrics_recorded metric => {:call_count => 1}
  end

  def test_add_method_tracer_keyword_args
    # Test we are not raising errors in e.g. Ruby 2.7
    self.class.add_method_tracer :method_with_kwargs

    in_transaction do
      _out, err = capture_io do
        method_with_kwargs('baz', arg2: false)
      end
      # We shouldn't be seeing warning messages in stdout
      refute_match %r{warn}, err
    end
  end

  def test_method_traced?
    assert !self.class.method_traced?(:method_to_be_traced)
    self.class.add_method_tracer :method_to_be_traced, METRIC
    assert self.class.method_traced?(:method_to_be_traced)
    begin
      self.class.remove_method_tracer :method_to_be_traced
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end
  end

  def test_tt_only
    self.class.add_method_tracer :method_c1, "c1", :push_scope => true
    self.class.add_method_tracer :method_c2, "c2", :metric => false
    self.class.add_method_tracer :method_c3, "c3", :push_scope => false

    in_transaction do
      method_c1
    end

    assert_metrics_recorded(['c1', 'c3'])
    assert_metrics_not_recorded('c2')
  end

  def test_nested_scope_tracer
    Insider.add_method_tracer :catcher, "catcher", :push_scope => true
    Insider.add_method_tracer :thrower, "thrower", :push_scope => true

    mock = Insider.new(@stats_engine)

    in_transaction do
      mock.catcher(0)
      mock.catcher(5)
    end

    assert_metrics_recorded({
      "catcher" => {:call_count => 2},
      "thrower" => {:call_count => 6}
    })

    sample = last_transaction_trace
    refute_nil sample
  end

  def test_add_same_tracer_twice
    @metric_name = METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC

    in_transaction do
      method_to_be_traced 1, 2, 3, true, METRIC
    end

    begin
      self.class.remove_method_tracer :method_to_be_traced
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end

    assert_metrics_recorded METRIC => {:call_count => 1, :total_call_time => 0.05}
  end

  def test_add_tracer_with_dynamic_metric
    metric_code = -> (*args) { "#{args[0]}.#{args[1]}" }
    @metric_name = metric_code
    expected_metric = "1.2"
    self.class.add_method_tracer :method_to_be_traced, metric_code

    in_transaction do
      method_to_be_traced 1, 2, 3, true, expected_metric
    end

    begin
      self.class.remove_method_tracer :method_to_be_traced
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end

    assert_metrics_recorded expected_metric => {:call_count => 1, :total_call_time => 0.05}
  end

  def test_trace_method_with_block
    self.class.add_method_tracer :method_with_block, METRIC
    in_transaction do
      method_with_block(1, 2, 3, true, METRIC) do
        advance_process_time 0.1
      end
    end

    assert_metrics_recorded METRIC => {:call_count => 1, :total_call_time => 0.15}
  end

  def test_remove
    self.class.add_method_tracer :method_to_be_traced, METRIC
    self.class.remove_method_tracer :method_to_be_traced

    method_to_be_traced 1, 2, 3, false, METRIC

    assert_metrics_not_recorded METRIC
  end

  def test_multiple_metrics__scoped
    metrics = %w[first second third]
    in_transaction do
      self.class.trace_execution_scoped metrics do
        advance_process_time 0.05
      end
    end

    assert_metrics_recorded({
      'first' => {:call_count => 1, :total_call_time => 0.05},
      'second' => {:call_count => 1, :total_call_time => 0.05},
      'third' => {:call_count => 1, :total_call_time => 0.05}
    })
  end

  def test_multiple_metrics__unscoped
    metrics = %w[first second third]
    self.class.trace_execution_unscoped metrics do
      advance_process_time 0.05
    end

    assert_metrics_recorded({
      'first' => {:call_count => 1, :total_call_time => 0.05},
      'second' => {:call_count => 1, :total_call_time => 0.05},
      'third' => {:call_count => 1, :total_call_time => 0.05}
    })
  end

  def test_exception
    begin
      metric = "hey"
      in_transaction do
        self.class.trace_execution_scoped(metric) do
          raise StandardError.new
        end
      end

      assert false # should never get here
    rescue StandardError
    end

    assert_metrics_recorded metric => {:call_count => 1}
  end

  def test_add_multiple_tracers
    in_transaction('test_txn') do
      self.class.add_method_tracer :method_to_be_traced, 'XX', :push_scope => false
      method_to_be_traced 1, 2, 3, true, nil
      self.class.remove_method_tracer :method_to_be_traced
      method_to_be_traced 1, 2, 3, true, nil
      self.class.add_method_tracer :method_to_be_traced, 'YY'
      method_to_be_traced 1, 2, 3, true, 'YY'
    end

    assert_metrics_recorded({
      ["YY", "test_txn"] => {:call_count => 1}
    })
  end

  def test_add_multiple_metrics
    in_transaction('test_txn') do
      self.class.add_method_tracer :method_to_be_traced, ['XX', 'YY', -> (*) { 'ZZ' }]
      method_to_be_traced 1, 2, 3, true, nil
    end

    assert_metrics_recorded([
      ['XX', 'test_txn'],
      'YY',
      'ZZ'
    ])
  end

  # This test validates that including the MethodTracer module does not pollute
  # the host class with any additional helper methods that are not part of the
  # official public API.
  def test_only_adds_methods_to_host_that_are_part_of_public_api
    host_class = Class.new { include ::NewRelic::Agent::MethodTracer }
    plain_class = Class.new

    host_instance_methods = host_class.new.methods
    plain_instance_methods = plain_class.new.methods

    added_methods = host_instance_methods - plain_instance_methods

    public_api_methods = [
      'trace_execution_unscoped',
      'trace_execution_scoped'
    ]

    assert_equal(public_api_methods.sort, added_methods.map(&:to_s).sort)
  end

  def test_method_tracer_on_basic_object
    proxy = MyProxyClass.new

    in_transaction 'test_txn' do
      proxy.hello
    end

    assert_metrics_recorded ['Custom/proxy/hello']
  end

  def trace_no_push_scope
    in_transaction 'test_txn' do
      self.class.add_method_tracer :method_to_be_traced, 'X', :push_scope => false
      method_to_be_traced 1, 2, 3, true, nil
      self.class.remove_method_tracer :method_to_be_traced
      method_to_be_traced 1, 2, 3, false, 'X'
    end

    assert_metrics_not_recorded ['X', 'test_txn']
  end

  def check_time(t1, t2)
    assert_in_delta t2, t1, 0.001
  end

  # =======================================================
  # test methods to be traced
  def method_to_be_traced(x, y, z, is_traced, expected_metric)
    advance_process_time 0.05
    assert x == 1
    assert y == 2
    assert z == 3
  end

  def method_with_block(x, y, z, is_traced, expected_metric, &block)
    advance_process_time 0.05
    assert x == 1
    assert y == 2
    assert z == 3
    yield
  end

  def method_with_kwargs(arg1, arg2: true)
    advance_process_time 0.05
    arg1 == arg2
  end

  def method_c1
    method_c2
  end

  def method_c2
    method_c3
  end

  def method_c3
  end

  def simple_method
  end
end
