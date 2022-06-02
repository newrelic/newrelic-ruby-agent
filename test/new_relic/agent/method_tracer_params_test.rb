# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'

class NewRelic::Agent::MethodTracerParamsTest < Minitest::Test
  METRIC = "metric"
  KEYWORD_DEPRECATED_WARNING = "Using the last argument as keyword parameters is deprecated"

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
    NewRelic::Agent.shutdown
    super
  end

  class UntracedMethods
    def expect_deprecation_warnings?
      RUBY_VERSION >= "2.7.0" && RUBY_VERSION < "3.0.0"
    end

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
      {args[0] => args[1]}
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

  def silence_expected_warnings
    capture_io { yield }
  end

  def assert_common_tracing_behavior traced_class
    assert_expected_results traced_class
    refute_deprecation_warnings traced_class
    call_expecting_warning_after_ruby_26 traced_class
  end

  [["untraced_methods", UntracedMethods],
    ["traced_methods", TracedMethods],
    ["traced_metric_methods", TracedMetricMethods],
    ["traced_metric_methods_unscoped", TracedMetricMethodsUnscoped]].each do |traced_class_name, traced_class|
    # We're doing it all in one big super test because order of invocation matters!
    # When many small test scenarios, if the tests for deprecation warnings emitted
    # by the compiler are not invoked first, then we miss our chance to capture
    # that output and assert/refute reliably.
    # This very large run ensures order of calls always happen in predictable order.
    define_method "test_expected_results_#{traced_class_name}" do
      expected = {foo: {bar: "foobar"}}
      expected369 = {1 => 3, 2 => 6, 3 => 9}
      instance = traced_class.new

      # Test deprecation warnings first!
      refute_deprecation_warning { instance.no_args }

      refute_deprecation_warning { instance.last_arg_expects_a_hash(:foo, {bar: "foobar"}) }
      refute_deprecation_warning { instance.last_arg_expects_a_hash(:foo, bar: "foobar") }

      refute_deprecation_warning { instance.wildcard_args(:foo, bar: "foobar") }
      refute_deprecation_warning { instance.wildcard_args(:foo, {bar: "foobar"}) }

      refute_deprecation_warning { instance.last_arg_is_a_keyword(:foo, bar: "foobar") }
      refute_deprecation_warning { instance.all_args_are_keywords(foo: :foo, bar: {bar: "foobar"}) }
      refute_deprecation_warning { instance.args_and_kwargs(:foo, bar: "foobar") }
      if RUBY_VERSION < "2.7.0"
        refute_deprecation_warning { instance.last_arg_is_a_keyword(:foo, {bar: "foobar"}) }
        refute_deprecation_warning { instance.args_and_kwargs(:foo, {bar: "foobar"}) }
      end

      # ensure behavior doesn't change by tracing methods!
      assert_equal expected, instance.no_args
      assert_equal expected, instance.last_arg_expects_a_hash(:foo, {bar: "foobar"})
      assert_equal expected, instance.last_arg_expects_a_hash(:foo, bar: "foobar")
      assert_equal expected, instance.wildcard_args(:foo, {bar: "foobar"})
      assert_equal expected, instance.wildcard_args(:foo, bar: "foobar")
      assert_equal expected, instance.args_and_kwargs(:foo, bar: "foobar")
      assert_equal expected369, instance.modifies_hash

      # This is what changes in 3.0!
      version_specific_expected = RUBY_VERSION >= "3.0.0" ? {foo: {}} : expected
      silence_expected_warnings { assert_equal version_specific_expected, instance.args_and_kwargs(:foo, {bar: "foobar"}) }
    end
  end
end
