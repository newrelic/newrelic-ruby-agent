# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','..','test_helper'))
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/attribute_filter'

class AttributesTest < Minitest::Test

  AttributeFilter = NewRelic::Agent::AttributeFilter

  def test_adding_custom_attributes
    attributes = create_attributes
    attributes.add_custom(:foo, "bar")
    assert_equal "bar", attributes.custom[:foo]
  end

  def test_adding_agent_attributes
    attributes = create_attributes
    attributes.add_agent(:foo, "bar")
    assert_equal "bar", attributes.agent[:foo]
  end

  def test_adding_intrinsic_attributes
    attributes = create_attributes
    attributes.add_intrinsic(:foo, "bar")
    assert_equal "bar", attributes.intrinsic[:foo]
  end

  def test_returns_hash_of_custom_attributes_for_destination
    with_config({}) do
      attributes = create_attributes
      attributes.add_custom(:foo, "bar")

      assert_equal({:foo => "bar"}, attributes.custom_for_destination(AttributeFilter::DST_TRANSACTION_TRACER))
    end
  end

  def test_returns_hash_of_agent_attributes_for_destination
    with_config({}) do
      attributes = create_attributes
      attributes.add_agent(:foo, "bar")

      assert_equal({:foo => "bar"}, attributes.agent_for_destination(AttributeFilter::DST_TRANSACTION_TRACER))
    end
  end

  def test_returns_hash_of_intrinsic_attributes_for_destination
    with_config({}) do
      attributes = create_attributes
      attributes.add_intrinsic(:foo, "bar")

      assert_equal({:foo => "bar"}, attributes.intrinsic_for_destination(AttributeFilter::DST_TRANSACTION_TRACER))
    end
  end

  def test_disabling_transaction_tracer_for_custom_attributes
    with_config({:'transaction_tracer.attributes.enabled' => false}) do
      attributes = create_attributes
      attributes.add_custom(:foo, "bar")

      assert_empty attributes.custom_for_destination(AttributeFilter::DST_TRANSACTION_TRACER)
    end
  end

  def test_disabling_transaction_tracer_for_agent_attributes
    with_config({:'transaction_tracer.attributes.enabled' => false}) do
      attributes = create_attributes
      attributes.add_agent(:foo, "bar")

      assert_empty attributes.agent_for_destination(AttributeFilter::DST_TRANSACTION_TRACER)
    end
  end

  def test_disabling_transaction_tracer_for_intrinsic_attributes
    with_config({:'transaction_tracer.attributes.enabled' => false}) do
      attributes = create_attributes
      attributes.add_intrinsic(:foo, "bar")

      assert_empty attributes.intrinsic_for_destination(AttributeFilter::DST_TRANSACTION_TRACER)
    end
  end

  def create_attributes
    filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
    NewRelic::Agent::Transaction::Attributes.new(filter)
  end
end