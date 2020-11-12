# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::MethodTracerParamsTest < Minitest::Test
  METRIC = "metric"
  KEYWORD_DEPRECATED_WARNING = "Using the last argument as keyword parameters is deprecated"

  def setup
    NewRelic::Agent::Tracer.clear_state

    NewRelic::Agent.manual_start
    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.clear_stats
    @metric_name ||= nil

    nr_freeze_time

    super
  end

  def teardown
    @stats_engine.clear_stats
    NewRelic::Agent.shutdown
    super
  end

  class UntracedMethods
    def no_args
      {foo: {bar: "foobar"}}
    end
    def last_arg_expects_a_hash foo, bar = {}
      {foo => bar}
    end
    def last_arg_is_a_keyword foo, bar:
      {foo => bar}
    end
    def all_args_are_keywords(foo: '', bar: '')
      {foo => bar}
    end
    def wildcard_args *args
      { args[0] => args[1] }
    end
    def args_and_kwargs *args, **kwargs
      {args[0] => kwargs}
    end

    def modifies_hash
      (1..3).each_with_object({}) do |i, hash|
        process(i, hash)
      end
    end
  
    def process(i, hash)
      hash[i] = i * 3
    end
  end

  class TracedMethods < UntracedMethods
    include NewRelic::Agent::MethodTracer
  
    add_method_tracer :no_args
    add_method_tracer :last_arg_expects_a_hash
    add_method_tracer :last_arg_is_a_keyword
    add_method_tracer :all_args_are_keywords
    add_method_tracer :wildcard_args
    add_method_tracer :args_and_kwargs
    add_method_tracer :process
  end
  
  class TracedMetricMethods < UntracedMethods
    add_method_tracer :no_args, METRIC
    add_method_tracer :last_arg_expects_a_hash, METRIC
    add_method_tracer :last_arg_is_a_keyword, METRIC
    add_method_tracer :all_args_are_keywords, METRIC
    add_method_tracer :wildcard_args, METRIC
    add_method_tracer :args_and_kwargs, METRIC
    add_method_tracer :process, METRIC
  end
   
  class TracedMetricMethodsUnscoped < UntracedMethods
    add_method_tracer :no_args, METRIC, push_scope: false
    add_method_tracer :last_arg_expects_a_hash, METRIC, push_scope: false
    add_method_tracer :last_arg_is_a_keyword, METRIC, push_scope: false
    add_method_tracer :all_args_are_keywords, METRIC, push_scope: false
    add_method_tracer :wildcard_args, METRIC, push_scope: false
    add_method_tracer :args_and_kwargs, METRIC, push_scope: false
    add_method_tracer :process, METRIC, push_scope: false
  end
  
  def assert_expected_results traced_class
    expected = {foo: {bar: "foobar"}}
    expected369 = {1=>3, 2=>6, 3=>9}
    instance = traced_class.new

    assert_equal expected, instance.no_args
    assert_equal expected, instance.last_arg_expects_a_hash(:foo, {bar: "foobar"})
    assert_equal expected, instance.last_arg_expects_a_hash(:foo, bar: "foobar")
    assert_equal expected, instance.wildcard_args(:foo, {bar: "foobar"})
    assert_equal expected, instance.wildcard_args(:foo, bar: "foobar")
    if RUBY_VERSION < "3.0.0"
      # This is what was removed in 3.0!
      assert_equal expected, instance.args_and_kwargs(:foo, {bar: "foobar"})
    end
    assert_equal expected, instance.args_and_kwargs(:foo, bar: "foobar")
    assert_equal expected369, instance.modifies_hash
  end

  def refute_deprecation_warning
    in_transaction do
      _out, err = capture_io { yield }
      refute_match KEYWORD_DEPRECATED_WARNING, err
      return err
    end
  end

  def assert_deprecation_warning
    in_transaction do
      _out, err = capture_io { yield }
      assert_match KEYWORD_DEPRECATED_WARNING, err
      return err
    end
  end

  def refute_deprecation_warnings traced_class
    instance = traced_class.new
    refute_deprecation_warning { instance.no_args }
    refute_deprecation_warning { instance.last_arg_expects_a_hash(:foo, {bar: "foobar"}) }
    refute_deprecation_warning { instance.last_arg_expects_a_hash(:foo, bar: "foobar") }
    refute_deprecation_warning { instance.wildcard_args(:foo, {bar: "foobar"}) }
    refute_deprecation_warning { instance.wildcard_args(:foo, bar: "foobar") }
    refute_deprecation_warning { instance.args_and_kwargs(:foo, {bar: "foobar"}) }
  end

  def call_expecting_warning_after_ruby_26 traced_class
    instance = traced_class.new

    refute_deprecation_warning { instance.last_arg_is_a_keyword(:foo, bar: "foobar") }
    refute_deprecation_warning { instance.all_args_are_keywords(foo: :foo, bar: {bar: "foobar"}) }
    refute_deprecation_warning { instance.args_and_kwargs(:foo, bar: "foobar") }
    if RUBY_VERSION < "3.0.0"
      refute_deprecation_warning { instance.last_arg_is_a_keyword(:foo, {bar: "foobar"}) }
      refute_deprecation_warning { instance.args_and_kwargs(:foo, {bar: "foobar"}) }
    end
  end

  def assert_common_tracing_behavior traced_class
    assert_expected_results traced_class
    refute_deprecation_warnings traced_class
    call_expecting_warning_after_ruby_26 traced_class
  end

  def test_untraced_methods
    assert_common_tracing_behavior UntracedMethods
    refute_metrics_recorded([METRIC])
  end

  def test_add_method_tracer_without_metrics
    assert_common_tracing_behavior TracedMethods
    refute_metrics_recorded([METRIC])
  end

  def test_add_method_tracer_with_metrics
    assert_common_tracing_behavior TracedMetricMethods
    assert_metrics_recorded([METRIC])
  end

  def test_add_method_tracer_with_metrics_unscoped
    assert_common_tracing_behavior TracedMetricMethodsUnscoped
    assert_metrics_recorded([METRIC])
  end

end
