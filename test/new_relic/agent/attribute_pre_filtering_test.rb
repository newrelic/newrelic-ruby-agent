# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/attribute_pre_filtering'

class AttributePreFilteringTest < Minitest::Test
  def test_string_to_regexp
    regexp = NewRelic::Agent::AttributePreFiltering.string_to_regexp('(?<!Old )Relic')

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
        assert_nil NewRelic::Agent::AttributePreFiltering.string_to_regexp(pattern)
        phony_logger.verify
      end
    end
  end

  def test_formulate_regexp_union
    option = :ton_up
    config = {option => [/^up$/, /\Alift\z/]}
    with_stubbed_config(config) do
      union = NewRelic::Agent::AttributePreFiltering.formulate_regexp_union(option)

      assert union.is_a?(Regexp)
      assert_match union, 'up', "Expected the Regexp union to match 'up'"
      assert_match union, 'lift', "Expected the Regexp union to match 'lift'"
    end
  end

  def test_formulate_regexp_union_with_single_regexp
    option = :micro_machines
    config = {option => [/4x4/]}
    with_stubbed_config(config) do
      union = NewRelic::Agent::AttributePreFiltering.formulate_regexp_union(option)

      assert union.is_a?(Regexp)
      assert_match union, '4x4 set 20', "Expected the Regexp union to match '4x4 set 20'"
    end
  end

  def test_formulate_regexp_union_when_option_is_not_set
    option = :soul_calibur2
    config = {option => []}

    with_stubbed_config(config) do
      assert_nil NewRelic::Agent::AttributePreFiltering.formulate_regexp_union(option)
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
        assert_nil NewRelic::Agent::AttributePreFiltering.formulate_regexp_union(:option_name_with_typo)
        phony_logger.verify
      end
    end
  end

  def test_pre_filter
    input = [{one: 1, two: 2}, [1, 2], 1, 2]
    options = {include: /one|1/}
    expected = [{one: 1}, [1], 1]
    values = NewRelic::Agent::AttributePreFiltering.pre_filter(input, options)

    assert_equal expected, values, "pre_filter returned >>#{values}<<, expected >>#{expected}<<"
  end

  def test_pre_filter_without_include_or_exclude
    input = [{one: 1, two: 2}, [1, 2], 1, 2]
    values = NewRelic::Agent::AttributePreFiltering.pre_filter(input, {})

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
      values = NewRelic::Agent::AttributePreFiltering.pre_filter(input, options)

      assert_equal input, values, "pre_filter returned >>#{values}<<, expected >>#{input}<<"
    end
  end

  def test_pre_filter_hash
    input = {one: 1, two: 2}
    options = {exclude: /1/}
    expected = {two: 2}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_hash(input, options)

    assert_equal expected, result, "pre_filter_hash returned >>#{result}<<, expected >>#{expected}<<"
  end

  # if a key matches an include, include the key/value pair even though the
  # value itself doesn't match the include
  def test_pre_filter_hash_includes_a_value_when_a_key_is_included
    input = {one: 1, two: 2}
    options = {include: /one/}
    expected = {one: 1}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_hash(input, options)

    assert_equal expected, result, "pre_filter_hash returned >>#{result}<<, expected >>#{expected}<<"
  end

  # even if a key matches an include, withhold the key/value pair if the
  # value matches an exclude
  def test_pre_filter_hash_still_applies_exclusions_to_hash_values
    input = {one: 1, two: 2}
    options = {include: /one|two/, exclude: /1/}
    expected = {two: 2}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_hash(input, options)

    assert_equal expected, result, "pre_filter_hash returned >>#{result}<<, expected >>#{expected}<<"
  end

  def test_pre_filter_hash_allows_an_empty_hash_to_pass_through
    input = {}
    options = {include: /one|two/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_hash(input, options)

    assert_equal input, result, "pre_filter_hash returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_hash_removes_the_hash_if_nothing_can_be_included
    input = {one: 1, two: 2}
    options = {include: /three/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_hash(input, options)

    assert_equal NewRelic::Agent::AttributePreFiltering::DISCARDED, result, "pre_filter_hash returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_array
    input = %w[one two 1 2]
    options = {exclude: /1|one/}
    expected = %w[two 2]
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_array(input, options)

    assert_equal expected, result, "pre_filter_array returned >>#{result}<<, expected >>#{expected}<<"
  end

  def test_pre_filter_array_allows_an_empty_array_to_pass_through
    input = []
    options = {exclude: /1|one/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_array(input, options)

    assert_equal input, result, "pre_filter_array returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_array_removes_the_array_if_nothing_can_be_included
    input = %w[one two 1 2]
    options = {exclude: /1|one|2|two/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_array(input, options)

    assert_equal NewRelic::Agent::AttributePreFiltering::DISCARDED, result, "pre_filter_array returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_scalar
    input = false
    options = {include: /false/, exclude: /true/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_scalar(input, options)

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_scalar_without_include
    input = false
    options = {exclude: /true/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_scalar(input, options)

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_scalar_without_exclude
    input = false
    options = {include: /false/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_scalar(input, options)

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_pre_filter_scalar_include_results_in_discarded
    input = false
    options = {include: /true/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_scalar(input, options)

    assert_equal NewRelic::Agent::AttributePreFiltering::DISCARDED, result, "pre_filter_scalar returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_scalar_exclude_results_in_discarded
    input = false
    options = {exclude: /false/}
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_scalar(input, options)

    assert_equal NewRelic::Agent::AttributePreFiltering::DISCARDED, result, "pre_filter_scalar returned >>#{result}<<, expected a 'discarded' result"
  end

  def test_pre_filter_scalar_without_include_or_exclude
    input = false
    result = NewRelic::Agent::AttributePreFiltering.pre_filter_scalar(input, {})

    assert_equal input, result, "pre_filter_scalar returned >>#{result}<<, expected >>#{input}<<"
  end

  def test_discarded?
    [nil, [], {}, false].each do |object|
      refute NewRelic::Agent::AttributePreFiltering.discarded?(object)
    end
  end

  private

  def with_stubbed_config(config = {}, &blk)
    NewRelic::Agent.stub :config, config do
      yield
    end
  end
end
