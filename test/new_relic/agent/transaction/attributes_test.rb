# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','..','test_helper'))
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/attribute_filter'

class AttributesTest < Minitest::Test

  Attributes      = NewRelic::Agent::Transaction::Attributes
  AttributeFilter = NewRelic::Agent::AttributeFilter

  def setup
    # Lots of tests that just want the default behavior, so make sure filter
    # is updated to that base
    NewRelic::Agent.instance.refresh_attribute_filter
  end

  def test_adds_custom_attribute
    attributes = create_attributes
    attributes.merge_custom_attributes(:foo => "bar")

    assert_equal({"foo" => "bar"}, attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER))
  end

  def test_disable_custom_attributes
    with_config({:'transaction_tracer.attributes.enabled' => false}) do
      attributes = create_attributes
      attributes.merge_custom_attributes(:foo => "bar")

      assert_empty attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
    end
  end

  def test_disable_custom_attributes_in_high_security_mode
    with_config(:high_security => true) do
      attributes = create_attributes
      attributes.merge_custom_attributes(:foo => "bar")

      assert_empty attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
    end
  end

  def test_disable_merging_custom_attributes_in_high_security_mode
    with_config(:high_security => true) do
      attributes = create_attributes
      attributes.merge_custom_attributes(:foo => "bar")

      assert_empty attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
    end
  end

  def test_merge_custom_attributes
      attributes = create_attributes
      params = {:foo => {:bar => "baz"}}
      attributes.merge_custom_attributes(params)
      assert_equal({"foo.bar" => "baz"}, attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER))
  end

  def test_adds_agent_attribute
    attributes = create_attributes
    attributes.add_agent_attribute(:foo, "bar", AttributeFilter::DST_ALL)

    assert_equal({:foo => "bar"}, attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER))
  end

  def test_disable_agent_attributes
    with_config({:'transaction_tracer.attributes.enabled' => false}) do
      attributes = create_attributes
      attributes.add_agent_attribute(:foo, "bar", AttributeFilter::DST_ALL)

      assert_empty attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
    end
  end

  def test_agent_attributes_obey_default_destinations
    attributes = create_attributes
    attributes.add_agent_attribute(:foo, "bar", AttributeFilter::DST_ERROR_COLLECTOR)

    assert_empty attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
  end

  def test_adds_intrinsic_attribute_to_only_traces_and_errors
    attributes = create_attributes
    attributes.add_intrinsic_attribute(:foo, "bar")

    expected = {:foo => "bar"}
    assert_equal(expected, attributes.intrinsic_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER))
    assert_equal(expected, attributes.intrinsic_attributes_for(AttributeFilter::DST_ERROR_COLLECTOR))

    assert_empty(attributes.intrinsic_attributes_for(AttributeFilter::DST_TRANSACTION_EVENTS))
    assert_empty(attributes.intrinsic_attributes_for(AttributeFilter::DST_BROWSER_MONITORING))
  end

  def test_intrinsic_attributes_arent_disabled_for_traces_and_errors
    with_config({:'transaction_tracer.attributes.enabled' => false}) do
      attributes = create_attributes
      attributes.add_intrinsic_attribute(:foo, "bar")

      expected = {:foo => "bar"}
      assert_equal(expected, attributes.intrinsic_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER))
      assert_equal(expected, attributes.intrinsic_attributes_for(AttributeFilter::DST_ERROR_COLLECTOR))

      assert_empty(attributes.intrinsic_attributes_for(AttributeFilter::DST_TRANSACTION_EVENTS))
      assert_empty(attributes.intrinsic_attributes_for(AttributeFilter::DST_BROWSER_MONITORING))
    end
  end

  MULTIBYTE_CHARACTER = "七"

  def test_truncates_multibyte_string
    # Leading single byte character makes byteslice yield invalid string
    value = "j" + MULTIBYTE_CHARACTER * 1000

    attributes = create_attributes
    attributes.merge_custom_attributes(:key => value)

    custom_attributes = attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
    result = custom_attributes["key"]
    if RUBY_VERSION >= "1.9.3"
      assert result.valid_encoding?
      assert result.bytesize < NewRelic::Agent::Transaction::Attributes::VALUE_LIMIT
    else
      assert_equal NewRelic::Agent::Transaction::Attributes::VALUE_LIMIT, result.bytesize
    end
  end

  def test_truncates_multibyte_symbol
    # Leading single byte character makes byteslice yield invalid string
    value = ("j" + MULTIBYTE_CHARACTER * 1000).to_sym

    attributes = create_attributes
    attributes.merge_custom_attributes(:key => value)

    custom_attributes = attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
    result = custom_attributes["key"]
    if RUBY_VERSION >= "1.9.3"
      assert result.valid_encoding?
      assert result.bytesize < NewRelic::Agent::Transaction::Attributes::VALUE_LIMIT
    else
      assert_equal NewRelic::Agent::Transaction::Attributes::VALUE_LIMIT, result.bytesize
    end
  end

  def test_limits_key_length
    key = "x" * (Attributes::KEY_LIMIT + 1)
    expects_logging(:warn, includes(key))

    attributes = create_attributes
    attributes.merge_custom_attributes(key => "")

    assert_custom_attributes_empty(attributes)
  end

  def test_limits_key_length_by_bytes
    key = MULTIBYTE_CHARACTER * Attributes::KEY_LIMIT
    expects_logging(:warn, includes(key))

    attributes = create_attributes
    attributes.merge_custom_attributes(key => "")

    assert_custom_attributes_empty(attributes)
  end

  def test_limits_key_length_symbol
    key = ("x" * (Attributes::KEY_LIMIT + 1)).to_sym
    expects_logging(:warn, includes(key.to_s))

    attributes = create_attributes
    attributes.merge_custom_attributes(key => "")

    assert_custom_attributes_empty(attributes)
  end

  def test_limits_key_length_on_merge_custom_attributes
    key = ("x" * (Attributes::KEY_LIMIT + 1)).to_sym
    expects_logging(:warn, includes(key.to_s))

    attributes = create_attributes
    attributes.merge_custom_attributes(key => "")

    assert_custom_attributes_empty(attributes)
  end

  def test_allows_non_string_key_type
    attributes = create_attributes
    attributes.merge_custom_attributes(1 => "value")

    assert_equal "value", custom_attributes(attributes)["1"]
  end

  def test_truncates_string_values
    value = "x" * 1000

    attributes = create_attributes
    attributes.merge_custom_attributes(:key => value)

    assert_equal Attributes::VALUE_LIMIT, custom_attributes(attributes)["key"].length
  end

  def test_truncates_symbol_values
    value = ("x" * 1000).to_sym

    attributes = create_attributes
    attributes.merge_custom_attributes(:key => value)

    assert_equal Attributes::VALUE_LIMIT, custom_attributes(attributes)["key"].length
  end

  def test_leaves_numbers_alone
    attributes = create_attributes
    attributes.merge_custom_attributes(:key => 42)

    assert_equal 42, custom_attributes(attributes)["key"]
  end

  def test_limits_attribute_count
    ::NewRelic::Agent.logger.expects(:warn).once

    attributes = create_attributes
    100.times do |i|
      attributes.merge_custom_attributes(i.to_s => i)
    end

    assert_equal Attributes::COUNT_LIMIT, custom_attributes(attributes).length
  end

  def test_merge_untrusted_agent_attributes
    with_config(:'attributes.include' => "request.parameters.*") do
      attributes = create_attributes
      params = {:foo => {:bar => "baz"}}
      attributes.merge_untrusted_agent_attributes(params, 'request.parameters', AttributeFilter::DST_NONE)
      assert_equal({"request.parameters.foo.bar" => "baz"}, agent_attributes(attributes))
    end
  end

  def test_merge_untrusted_agent_attributes_drops_long_keys
    with_config(:'attributes.include' => "request.parameters.*") do
      attributes = create_attributes
      params = {
        "a"*256 => "too long",
        "foo" => "bar"
      }
      attributes.merge_untrusted_agent_attributes(params, 'request.parameters', AttributeFilter::DST_NONE)
      assert_equal({"request.parameters.foo" => "bar"}, agent_attributes(attributes))
    end
  end

  def test_merge_untrusted_agent_attributes_disallowed_in_high_security
    with_config(:high_security => true, :'attributes.include' => "request.parameters.*") do
      attributes = create_attributes
      params = { "sneaky" => "code" }

      attributes.merge_untrusted_agent_attributes('request.parameters', params, AttributeFilter::DST_NONE)
      assert_empty agent_attributes(attributes)
    end
  end

  def create_attributes
    filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
    NewRelic::Agent::Transaction::Attributes.new(filter)
  end

  def custom_attributes(attributes)
    attributes.custom_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
  end

  def assert_custom_attributes_empty(attributes)
    assert_empty custom_attributes(attributes)
  end

  def agent_attributes(attributes)
    attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)
  end
end
