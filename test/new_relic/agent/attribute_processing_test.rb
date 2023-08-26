# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/attribute_processing'

class AttributeProcessingTest < Minitest::Test
  def test_flatten_and_coerce_handles_nested_hashes
    params = {'user' =>
      {'addresses' =>
        [
          {'street' => '123 Street', 'city' => 'City', 'state' => 'ST', 'zip' => '12345'},
          {'street' => '123 Blvd', 'city' => 'City2', 'state' => 'ST2', 'zip' => '54321'}
        ]}}

    expected = {
      'request.parameters.user.addresses.0.street' => '123 Street',
      'request.parameters.user.addresses.0.city' => 'City',
      'request.parameters.user.addresses.0.state' => 'ST',
      'request.parameters.user.addresses.0.zip' => '12345',
      'request.parameters.user.addresses.1.street' => '123 Blvd',
      'request.parameters.user.addresses.1.city' => 'City2',
      'request.parameters.user.addresses.1.state' => 'ST2',
      'request.parameters.user.addresses.1.zip' => '54321'
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params, 'request.parameters')

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_coerces_values
    params = {
      'v1' => Class.new,
      'v2' => :symbol,
      'v3' => 1.01
    }

    expected = {
      'request.parameters.v1' => '#<Class>',
      'request.parameters.v2' => 'symbol',
      'request.parameters.v3' => 1.01
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params, 'request.parameters')

    assert_equal(expected, actual)
  end

  def test_prefix_optional_for_flatten_and_coerce
    params = {:foo => {:bar => %w[v1 v2]}}

    expected = {
      'foo.bar.0' => 'v1',
      'foo.bar.1' => 'v2'
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_prefix_optional_for_flatten_and_coerce_with_initial_array_argument
    params = [:foo => {:bar => %w[v1 v2]}]

    expected = {
      '0.foo.bar.0' => 'v1',
      '0.foo.bar.1' => 'v2'
    }

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_replaces_empty_hash_with_string_representation
    params = {:foo => {:bar => {}}}

    expected = {'foo.bar' => '{}'}

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_replaces_empty_array_with_string_representation
    params = {:foo => {:bar => []}}

    expected = {'foo.bar' => '[]'}

    actual = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal(expected, actual)
  end

  def test_flatten_and_coerce_coerce_handles_values_mixed_and_complex_types_properly
    assert_equal(
      {
        'foo' => 1.0,
        'bar' => 2,
        'bang' => 'woot',
        'ok' => 'dokey',
        'yes' => '[]',
        'yup' => '{}',
        'yayuh' => '#<Rational>',
        'truthy' => true,
        'falsy' => false
      },
      NewRelic::Agent::AttributeProcessing.flatten_and_coerce(
        {
          'foo' => 1.0,
          'bar' => 2,
          'bang' => 'woot',
          'ok' => :dokey,
          'yes' => [],
          'yup' => {},
          'yayuh' => Rational(1),
          'truthy' => true,
          'falsy' => false
        }
      )
    )
  end

  def test_flatten_and_coerce_turns_nan_or_infinity_into_null_and_then_dropped
    assert_empty(
      NewRelic::Agent::AttributeProcessing.flatten_and_coerce(
        {
          'nan' => Float::NAN,
          'inf' => Float::INFINITY,
          'ninf' => -Float::INFINITY
        }
      )
    )
  end

  def test_flatten_and_coerce_logs_warning_with_unexpected_arguments
    expects_logging(:warn, all_of(includes('Unexpected object'), includes('flatten_and_coerce')))
    NewRelic::Agent::AttributeProcessing.flatten_and_coerce(Object.new)
  end

  def test_flatten_and_coerce_calls_a_block_key_and_value_when_provided
    params = {:foo => {:bar => %w[qux quux]}}
    yielded = {}

    NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params) { |k, v| yielded[k] = v }

    expected = {'foo.bar.0' => 'qux', 'foo.bar.1' => 'quux'}

    assert_equal expected, yielded
  end

  def test_flatten_and_coerce_leaves_nils_alone
    params = {:referer => nil}
    expected = {}

    result = NewRelic::Agent::AttributeProcessing.flatten_and_coerce(params)

    assert_equal expected, result
  end

  def test_string_to_regexp
    regexp = NewRelic::Agent::AttributeProcessing.string_to_regexp('(?<!Old )Relic')

    assert_match regexp, 'New Relic'
    refute_match regexp, 'Old Relic'
  end

  def test_string_to_regexp_with_exception
    skip_unless_minitest5_or_above

    pattern = 'pattern as string'
    error_msg = 'kaboom'
    phony_logger = Minitest::Mock.new
    phony_logger.expect :warn, nil, [/Failed to initialize.*#{error_msg}/]
    NewRelic::Agent.stub :logger, phony_logger do
      Regexp.stub :new, proc { |_| raise error_msg }, [pattern] do
        assert_nil NewRelic::Agent::AttributeProcessing.string_to_regexp(pattern)
        phony_logger.verify
      end
    end
  end

  def test_formulate_regexp_union
    option = :ton_up
    config = {option => [/^up$/, /\Alift\z/]}
    with_stubbed_config(config) do
      union = NewRelic::Agent::AttributeProcessing.formulate_regexp_union(option)

      assert union.is_a?(Regexp)
      assert_match union, 'up', "Expected the Regexp union to match 'up'"
      assert_match union, 'lift', "Expected the Regexp union to match 'lift'"
    end
  end

  def test_formulate_regexp_union_with_single_regexp
    option = :micro_machines
    config = {option => [/4x4/]}
    with_stubbed_config(config) do
      union = NewRelic::Agent::AttributeProcessing.formulate_regexp_union(option)

      assert union.is_a?(Regexp)
      assert_match union, '4x4 set 20', "Expected the Regexp union to match '4x4 set 20'"
    end
  end

  def test_formulate_regexp_union_when_option_is_not_set
    option = :soul_calibur2
    config = {option => []}

    with_stubbed_config(config) do
      assert_nil NewRelic::Agent::AttributeProcessing.formulate_regexp_union(option)
    end
  end

  def test_formulate_regexp_union_with_exception_is_raised
    skip_unless_minitest5_or_above

    with_stubbed_config do
      # formulate_regexp_union expects to be working with options that have an
      # empty array for a default value. If it receives a bogus option, an
      # exception will be raised, caught, and logged and a nil will be returned.
      phony_logger = Minitest::Mock.new
      phony_logger.expect :warn, nil, [/Failed to formulate/]
      NewRelic::Agent.stub :logger, phony_logger do
        assert_nil NewRelic::Agent::AttributeProcessing.formulate_regexp_union(:option_name_with_typo)
        phony_logger.verify
      end
    end
  end

  def test_pre_filter
    input = [{one: 1, two: 2}, [1, 2], 1, 2]
    options = {include: /one|1/}
    expected = [{one: 1}, [1], 1]
    values = NewRelic::Agent::AttributeProcessing.pre_filter(input, options)

    assert_equal expected, values, "pre_filter returned >>#{values}<<, expected >>#{expected}<<"
  end

  def test_pre_filter_without_include_or_exclude
    input = [{one: 1, two: 2}, [1, 2], 1, 2]
    values = NewRelic::Agent::AttributeProcessing.pre_filter(input, {})

    assert_equal input, values, "pre_filter returned >>#{values}<<, expected >>#{input}<<"
  end

  def test_pre_filter_with_prefix_that_will_be_filtered_out_after_pre_filter
    skip_unless_minitest5_or_above

    input = [{one: 1, two: 2}, [1, 2], 1, 2]
    namespace = 'something filtered out by default'
    # config has specified an include pattern for pre filtration, but regular
    # filtration will block all of the content anyhow, so expect a no-op result
    options = {include: /one|1/, attribute_namespace: namespace}
    NewRelic::Agent.instance.attribute_filter.stub :might_allow_prefix?, false, [namespace] do
      values = NewRelic::Agent::AttributeProcessing.pre_filter(input, options)

      assert_equal input, values, "pre_filter returned >>#{values}<<, expected >>#{input}<<"
    end
  end

  def test_pre_filter_hash
    input = {one: 1, two: 2}
    options = {exclude: /1/}
    expected = {two: 2}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_hash(input, options)

    assert_equal expected, result, "pre_filter_hash returned >>#{result}<<, expected >>#{expected}<<"
  end

  # if a key matches an include, include the key/value pair even though the
  # value itself doesn't match the include
  def test_pre_filter_hash_includes_a_value_when_a_key_is_included
    input = {one: 1, two: 2}
    options = {include: /one/}
    expected = {one: 1}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_hash(input, options)

    assert_equal expected, result, "pre_filter_hash returned >>#{result}<<, expected >>#{expected}<<"
  end

  # even if a key matches an include, withhold the key/value pair if the
  # value matches an exclude
  def test_pre_filter_hash_still_applies_exclusions_to_hash_values
    input = {one: 1, two: 2}
    options = {include: /one|two/, exclude: /1/}
    expected = {two: 2}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_hash(input, options)

    assert_equal expected, result, "pre_filter_hash returned >>#{result}<<, expected >>#{expected}<<"
  end

  def test_pre_filter_hash_allows_an_empty_hash_to_pass_through
    input = {}
    options = {include: /one|two/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_hash(input, options)

    assert_equal input, result, "pre_filter_hash returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_hash_removes_the_hash_if_nothing_can_be_included
    input = {one: 1, two: 2}
    options = {include: /three/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_hash(input, options)

    assert_equal NewRelic::Agent::AttributeProcessing::DISCARDED, result, "pre_filter_hash returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_array
    input = %w[one two 1 2]
    options = {exclude: /1|one/}
    expected = %w[two 2]
    result = NewRelic::Agent::AttributeProcessing.pre_filter_array(input, options)

    assert_equal expected, result, "pre_filter_array returned >>#{result}<<, expected >>#{expected}<<"
  end

  def test_pre_filter_array_allows_an_empty_array_to_pass_through
    input = []
    options = {exclude: /1|one/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_array(input, options)

    assert_equal input, result, "pre_filter_array returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_array_removes_the_array_if_nothing_can_be_included
    input = %w[one two 1 2]
    options = {exclude: /1|one|2|two/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_array(input, options)

    assert_equal NewRelic::Agent::AttributeProcessing::DISCARDED, result, "pre_filter_array returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_scalar
    input = false
    options = {include: /false/, exclude: /true/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_scalar(input, options)

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_scalar_without_include
    input = false
    options = {exclude: /true/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_scalar(input, options)

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_scalar_without_exclude
    input = false
    options = {exclude: /true/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_scalar(input, options)

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_scalar_include_results_in_discarded
    input = false
    options = {include: /true/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_scalar(input, options)

    assert_equal NewRelic::Agent::AttributeProcessing::DISCARDED, result, "pre_filter_scalar returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_scalar_exclude_results_in_discarded
    input = false
    options = {exclude: /false/}
    result = NewRelic::Agent::AttributeProcessing.pre_filter_scalar(input, options)

    assert_equal NewRelic::Agent::AttributeProcessing::DISCARDED, result, "pre_filter_scalar returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_scalar_without_include_or_exclude
    input = false
    result = NewRelic::Agent::AttributeProcessing.pre_filter_scalar(input, {})

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_discarded?
    [nil, [], {}, false].each do |object|
      refute NewRelic::Agent::AttributeProcessing.discarded?(object)
    end
  end

  private

  def with_stubbed_config(config = {}, &blk)
    NewRelic::Agent.stub :config, config do
      yield
    end
  end
end
