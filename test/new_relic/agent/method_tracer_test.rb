# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/mock_scope_listener'

class Module
  def method_traced?(method_name, metric_name)
    traced_method_prefix = _traced_method_name(method_name, metric_name)

    method_defined? traced_method_prefix
  end
end

class Insider
  def initialize(stats_engine)
    @stats_engine = stats_engine
  end
  def catcher(level=0)
    thrower(level) if level>0
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
      thrower(level-1)
    end
  end
end

module NewRelic
  module Agent
    extend self
    def module_method_to_be_traced (x, testcase)
      testcase.assert_equal 'x',  x
    end
  end
end

module TestModuleWithLog
  extend self
  def other_method
    #just here to be traced
    log "12345"
  end

  def log( msg )
    msg
  end
  include NewRelic::Agent::MethodTracer
  add_method_tracer :other_method, 'Custom/foo/bar'
end

class MyClass
  def self.class_method
  end

  class << self
    include NewRelic::Agent::MethodTracer
    add_method_tracer :class_method
  end
end

class NewRelic::Agent::MethodTracerTest < Minitest::Test
  attr_reader :stats_engine

  def setup
    NewRelic::Agent::TransactionState.tl_clear_for_testing

    NewRelic::Agent.manual_start
    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.clear_stats
    @scope_listener = NewRelic::Agent::MockScopeListener.new
    @old_sampler = NewRelic::Agent.instance.transaction_sampler
    NewRelic::Agent.instance.stubs(:transaction_sampler).returns(@scope_listener)

    freeze_time

    super
  end

  def teardown
    @stats_engine.clear_stats
    begin
      self.class.remove_method_tracer :method_to_be_traced, @metric_name if @metric_name
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end

    @metric_name = nil
    super
  end

  def test_preserve_logging
    assert_equal '12345', TestModuleWithLog.other_method
  end

  def test_record_metrics_does_not_raise_outside_transaction
    state = NewRelic::Agent::TransactionState.tl_get
    NewRelic::Agent::MethodTracerHelpers.record_metrics(state, 'a', ['b'], 12, 10, :metric => true)

    expected = { :call_count => 1, :total_call_time => 12, :total_exclusive_time => 10 }
    assert_metrics_recorded('a' => expected, 'b' => expected)
  end

  def test_trace_execution_scoped_records_metric_data
    metric = "hello"
    self.class.trace_execution_scoped(metric) do
      advance_time 0.05
    end

    stats = @stats_engine.get_stats(metric)
    check_time 0.05, stats.total_call_time
    assert_equal 1, stats.call_count
  end

  def test_trace_execution_scoped_with_no_metrics_skips_out
    self.class.trace_execution_scoped([]) do
      advance_time 0.05
    end

    assert_metrics_recorded_exclusive([])
  end

  def test_trace_execution_scoped_records_metric_data_from_callback
    metric = "hello"
    callback_metric = "goodbye"
    callback = Proc.new { callback_metric }
    options = { :additional_metrics_callback => callback }

    self.class.trace_execution_scoped(metric, options) do
      advance_time 0.05
    end

    stats = @stats_engine.get_stats(callback_metric)
    check_time 0.05, stats.total_call_time
    assert_equal 1, stats.call_count
  end

  def test_trace_execution_scoped_pushes_transaction_scope
    self.class.trace_execution_scoped('yeap') do
      'ptoo'
    end
    assert_equal 'yeap',  @scope_listener.scopes.last
  end

  def test_basic__original_api
    metric = "hello"
    self.class.trace_method_execution(metric, true, true, true) do
      advance_time(0.05)
    end

    stats = @stats_engine.get_stats(metric)
    check_time 0.05, stats.total_call_time
    assert_equal 1, stats.call_count
    assert_equal metric,  @scope_listener.scopes.last
  end

  METRIC = "metric"
  def test_add_method_tracer
    @metric_name = METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC

    method_to_be_traced 1,2,3,true,METRIC

    begin
      self.class.remove_method_tracer :method_to_be_traced, METRIC
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end


    stats = @stats_engine.get_stats(METRIC)
    check_time 0.05, stats.total_call_time
    assert_equal 1, stats.call_count
    assert_equal METRIC, @scope_listener.scopes.last
  end

  def test_add_method_tracer__default
    self.class.add_method_tracer :simple_method

    simple_method

    stats = @stats_engine.get_stats("Custom/#{self.class.name}/simple_method")
    assert stats.call_count == 1
  end

  def test_add_class_method_tracer
    MyClass.class_method
    stats = @stats_engine.get_stats("Custom/MyClass/Class/class_method")
    assert stats.call_count == 1
  end

  def test_add_anonymous_class_method_tracer
    cls = Class.new do
      def instance_method; end
      include NewRelic::Agent::MethodTracer
      add_method_tracer :instance_method
    end

    cls.new.instance_method
    # require 'pry'; binding.pry
    stats = @stats_engine.get_stats("Custom/AnonymousClass/instance_method")
    assert stats.call_count == 1
  end

  def test_add_method_tracer__reentry
    self.class.add_method_tracer :simple_method
    self.class.add_method_tracer :simple_method
    self.class.add_method_tracer :simple_method

    simple_method

    stats = @stats_engine.get_stats("Custom/#{self.class.name}/simple_method")
    assert stats.call_count == 1
  end

  def test_method_traced?
    assert !self.class.method_traced?(:method_to_be_traced, METRIC)
    self.class.add_method_tracer :method_to_be_traced, METRIC
    assert self.class.method_traced?(:method_to_be_traced, METRIC)
    begin
      self.class.remove_method_tracer :method_to_be_traced, METRIC
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end
  end

  def test_tt_only
    assert @scope_listener.scopes.empty?

    self.class.add_method_tracer :method_c1, "c1", :push_scope => true
    self.class.add_method_tracer :method_c2, "c2", :metric => false
    self.class.add_method_tracer :method_c3, "c3", :push_scope => false

    method_c1

    assert_metrics_recorded(['c1', 'c3'])
    assert_metrics_not_recorded('c2')

    assert_equal ['c2', 'c1'], @scope_listener.scopes
  end

  def test_nested_scope_tracer
    Insider.add_method_tracer :catcher, "catcher", :push_scope => true
    Insider.add_method_tracer :thrower, "thrower", :push_scope => true

    # This expects to use the real transaction sampler, so stub it back
    NewRelic::Agent.instance.stubs(:transaction_sampler).returns(@old_sampler)

    mock = Insider.new(@stats_engine)
    mock.catcher(0)
    mock.catcher(5)

    stats = @stats_engine.get_stats("catcher")
    assert_equal 2, stats.call_count
    stats = @stats_engine.get_stats("thrower")
    assert_equal 6, stats.call_count
    sample = @old_sampler.harvest!
    refute_nil sample
  end

  def test_add_same_tracer_twice
    @metric_name = METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC

    method_to_be_traced 1,2,3,true,METRIC

    begin
      self.class.remove_method_tracer :method_to_be_traced, METRIC
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end

    stats = @stats_engine.get_stats(METRIC)
    check_time 0.05, stats.total_call_time
    assert_equal 1, stats.call_count
    assert_equal METRIC, @scope_listener.scopes.last
    assert(METRIC != @scope_listener.scopes[-2],
           'duplicate scope detected when redundant tracer is present')
  end

  def test_add_tracer_with_dynamic_metric
    metric_code = '#{args[0]}.#{args[1]}'
    @metric_name = metric_code
    expected_metric = "1.2"
    self.class.add_method_tracer :method_to_be_traced, metric_code

    method_to_be_traced 1,2,3,true,expected_metric

    begin
      self.class.remove_method_tracer :method_to_be_traced, metric_code
    rescue RuntimeError
      # ignore 'no tracer' errors from remove method tracer
    end

    stats = @stats_engine.get_stats(expected_metric)
    check_time 0.05, stats.total_call_time
    assert_equal 1, stats.call_count
    assert_equal expected_metric, @scope_listener.scopes.last
  end

  def test_trace_method_with_block
    self.class.add_method_tracer :method_with_block, METRIC

    method_with_block(1,2,3,true,METRIC) do
      advance_time 0.1
    end

    stats = @stats_engine.get_stats(METRIC)
    check_time 0.15, stats.total_call_time
    assert_equal 1, stats.call_count
    assert_equal METRIC, @scope_listener.scopes.last
  end

  def test_trace_module_method
    NewRelic::Agent.add_method_tracer :module_method_to_be_traced, '#{args[0]}'
    NewRelic::Agent.module_method_to_be_traced "x", self
    NewRelic::Agent.remove_method_tracer :module_method_to_be_traced, '#{args[0]}'
  end

  def test_remove
    self.class.add_method_tracer :method_to_be_traced, METRIC
    self.class.remove_method_tracer :method_to_be_traced, METRIC

    method_to_be_traced 1,2,3,false,METRIC

    stats = @stats_engine.get_stats(METRIC)
    assert stats.call_count == 0
  end

  def self.static_method(x, testcase, is_traced)
    testcase.assert_equal 'x',  x
  end

  def trace_trace_static_method
    self.add_method_tracer :static_method, '#{args[0]}'
    self.class.static_method "x", self, true
    assert_equal 'x', @scope_listener.scopes.last
    @scope_listener = NewRelic::Agent::MockScopeListener.new
    self.remove_method_tracer :static_method, '#{args[0]}'
    self.class.static_method "x", self, false
    assert_nil @scope_listener.scopes.last
  end

  def test_multiple_metrics__scoped
    metrics = %w[first second third]
    self.class.trace_execution_scoped metrics do
      advance_time 0.05
    end
    elapsed = @stats_engine.get_stats('first').total_call_time
    metrics.map{|name| @stats_engine.get_stats name}.each do | m |
      assert_equal 1, m.call_count
      assert_equal elapsed, m.total_call_time
    end
    assert_equal 'first', @scope_listener.scopes.last
  end

  def test_multiple_metrics__unscoped
    metrics = %w[first second third]
    self.class.trace_execution_unscoped metrics do
      advance_time 0.05
    end
    elapsed = @stats_engine.get_stats('first').total_call_time
    metrics.map{|name| @stats_engine.get_stats name}.each do | m |
      assert_equal 1, m.call_count
      assert_equal elapsed, m.total_call_time
    end
    assert @scope_listener.scopes.empty?
  end

  def test_exception
    begin
      metric = "hey"
      self.class.trace_execution_scoped(metric) do
        raise StandardError.new
      end

      assert false # should never get here
    rescue StandardError
      # make sure the scope gets popped
      assert_equal metric, @scope_listener.scopes.last
    end

    stats = @stats_engine.get_stats metric
    assert_equal 1, stats.call_count
  end

  def test_add_multiple_tracers
    self.class.add_method_tracer :method_to_be_traced, 'XX', :push_scope => false
    method_to_be_traced 1,2,3,true,nil
    self.class.add_method_tracer :method_to_be_traced, 'YY'
    method_to_be_traced 1,2,3,true,'YY'
    self.class.remove_method_tracer :method_to_be_traced, 'YY'
    method_to_be_traced 1,2,3,true,nil
    self.class.remove_method_tracer :method_to_be_traced, 'XX'
    method_to_be_traced 1,2,3,false,'XX'

    assert_equal ['YY'], @scope_listener.scopes
  end

  def test_add_method_tracer_module_double_inclusion
    mod = Module.new { def traced_method; end }
    cls = Class.new { include mod }

    mod.module_eval do
      include NewRelic::Agent::MethodTracer
      add_method_tracer :traced_method
    end

    cls.new.traced_method
  end

  # This test validates that including the MethodTracer module does not pollute
  # the host class with any additional helper methods that are not part of the
  # official public API.
  def test_only_adds_methods_to_host_that_are_part_of_public_api
    host_class  = Class.new { include ::NewRelic::Agent::MethodTracer }
    plain_class = Class.new

    host_instance_methods  = host_class.new.methods
    plain_instance_methods = plain_class.new.methods

    added_methods = host_instance_methods - plain_instance_methods

    public_api_methods = [
      'trace_execution_unscoped',
      'trace_execution_scoped',
      'trace_method_execution',            # deprecated
      'trace_method_execution_with_scope', # deprecated
      'trace_method_execution_no_scope',   # deprecated
      'get_stats_scoped',                  # deprecated
      'get_stats_unscoped'                 # deprecated
    ]

    assert_equal(public_api_methods.sort, added_methods.map(&:to_s).sort)
  end

  def test_get_stats_unscoped
    host_class = Class.new { include ::NewRelic::Agent::MethodTracer }
    expected_stats = NewRelic::Agent.get_stats('foobar')
    stats = host_class.new.get_stats_unscoped('foobar')
    assert_same(expected_stats, stats)
  end

  def test_get_stats_scoped
    host_class = Class.new { include ::NewRelic::Agent::MethodTracer }
    expected_stats = NewRelic::Agent.get_stats('foobar', true)
    stats = host_class.new.get_stats_scoped('foobar', false)
    assert_same(expected_stats, stats)
  end

  def trace_no_push_scope
    self.class.add_method_tracer :method_to_be_traced, 'X', :push_scope => false
    method_to_be_traced 1,2,3,true,nil
    self.class.remove_method_tracer :method_to_be_traced, 'X'
    method_to_be_traced 1,2,3,false,'X'

    assert_nil @scope_listener.scopes
  end

  def check_time(t1, t2)
    assert_in_delta t2, t1, 0.001
  end

  # =======================================================
  # test methods to be traced
  def method_to_be_traced(x, y, z, is_traced, expected_metric)
    advance_time 0.05
    assert x == 1
    assert y == 2
    assert z == 3
  end

  def method_with_block(x, y, z, is_traced, expected_metric, &block)
    advance_time 0.05
    assert x == 1
    assert y == 2
    assert z == 3
    yield
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
