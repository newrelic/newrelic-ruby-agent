# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))
class NewRelic::MetricSpecTest < Minitest::Test

  def test_equal
    spec1 = NewRelic::MetricSpec.new('Controller')
    spec2 = NewRelic::MetricSpec.new('Controller', nil)

    assert spec1.eql?(NewRelic::MetricSpec.new('Controller'))
    assert spec2.eql?(NewRelic::MetricSpec.new('Controller', nil))
    assert spec1.eql?(spec2)
    assert !spec2.eql?(NewRelic::MetricSpec.new('Controller', '/dude'))
  end

  define_method(:'test_<=>') do
    s1 = NewRelic::MetricSpec.new('ActiveRecord')
    s2 = NewRelic::MetricSpec.new('Controller')
    assert_equal [s1, s2].sort, [s1,s2]
    assert_equal [s2, s1].sort, [s1,s2]

    s1 = NewRelic::MetricSpec.new('Controller', nil)
    s2 = NewRelic::MetricSpec.new('Controller', 'hap')
    assert_equal [s2, s1].sort, [s1, s2]
    assert_equal [s1, s2].sort, [s1, s2]

    s1 = NewRelic::MetricSpec.new('Controller', 'hap')
    s2 = NewRelic::MetricSpec.new('Controller', nil)
    assert_equal [s2, s1].sort, [s2, s1]
    assert_equal [s1, s2].sort, [s2, s1]

    s1 = NewRelic::MetricSpec.new('Controller')
    s2 = NewRelic::MetricSpec.new('Controller')
    assert_equal [s2, s1].sort, [s2, s1] # unchanged due to no sort criteria
    assert_equal [s1, s2].sort, [s1, s2] # unchanged due to no sort criteria

    s1 = NewRelic::MetricSpec.new('Controller', nil)
    s2 = NewRelic::MetricSpec.new('Controller', nil)
    assert_equal [s2, s1].sort, [s2, s1] # unchanged due to no sort criteria
    assert_equal [s1, s2].sort, [s1, s2] # unchanged due to no sort criteria
  end

  # test to make sure the MetricSpec class can serialize to json
  if defined?(::ActiveSupport)
    def test_json
      spec = NewRelic::MetricSpec.new("controller", "metric#find")

      import = ::ActiveSupport::JSON.decode(spec.to_json)

      compare_spec(spec, import)

      stats = NewRelic::Agent::Stats.new

      import = ::ActiveSupport::JSON.decode(stats.to_json)

      compare_stat(stats, import)

      metric_data = NewRelic::MetricData.new(spec, stats)

      import = ::ActiveSupport::JSON.decode(metric_data.to_json)

      compare_metric_data(metric_data, import)
    end
  else
    puts "Skipping tests in #{__FILE__} because ActiveSupport is unavailable"
  end

  def test_initialize_truncates_name_and_scope
    long_name = "a" * 300
    long_scope = "b" * 300
    spec = NewRelic::MetricSpec.new(long_name, long_scope)
    assert_equal("a" * 255, spec.name, "should have shortened the name")
    assert_equal("b" * 255, spec.scope, "should have shortened the scope")
  end

  # These next three tests are here only because rpm_site uses our MetricSpec
  # class in silly ways (specifically, it passes in non-String values for
  # name/scope). If we can get rid of those silly usages, we can remove these
  # tests.

  def test_initialize_can_take_a_nil_name
    spec = NewRelic::MetricSpec.new(nil)

    assert_equal('', spec.name)
    assert_equal('', spec.scope)
  end

  def test_initialize_can_take_a_non_string_name
    name  = string_wrapper_class.new("name")

    spec = NewRelic::MetricSpec.new(name)

    assert_equal('name',  spec.name)
    assert_equal('',      spec.scope)
  end

  def test_initialize_can_take_a_non_string_scope
    name  = "name"
    scope = string_wrapper_class.new("scope")

    spec = NewRelic::MetricSpec.new(name, scope)

    assert_equal('name',  spec.name)
    assert_equal('scope', spec.scope)
  end

  private

  def string_wrapper_class
    Class.new do
      def initialize(value)
        @value = value
      end

      def to_s
        @value
      end
    end
  end

  def compare_spec(spec, import)
    assert_equal 2, import.length
    assert_equal spec.name, import['name']
    assert_equal spec.scope, import['scope']
  end

  def compare_stat(stats, import)
    assert_equal 6, import.length
    assert_equal stats.total_call_time, import['total_call_time']
    assert_equal stats.max_call_time, import['max_call_time']
    assert_equal stats.min_call_time, import['min_call_time']
    assert_equal stats.sum_of_squares, import['sum_of_squares']
    assert_equal stats.call_count, import['call_count']
    assert_equal stats.total_exclusive_time, import['total_exclusive_time']
  end

  def compare_metric_data(metric_data, import)
    assert_equal 2, import.length
    compare_spec(metric_data.metric_spec, import['metric_spec'])
    compare_stat(metric_data.stats, import['stats'])
  end
end
