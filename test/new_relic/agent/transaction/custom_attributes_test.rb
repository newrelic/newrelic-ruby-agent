# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','..','test_helper'))
require 'new_relic/agent/transaction/custom_attributes'
require 'new_relic/agent/attribute_filter'

class CustomAttributesTest < Minitest::Test

  AttributeFilter = NewRelic::Agent::AttributeFilter

  def setup
    filter = AttributeFilter.new(NewRelic::Agent.config)
    @attributes = NewRelic::Agent::Transaction::CustomAttributes.new(filter)
  end

  def test_limits_key_length
    key = ("x" * 256)
    expects_logging(:warn, includes(key))

    @attributes.add(key, "")
    assert_equal 0, @attributes.length
  end

  def test_limits_key_length_symbol
    key = ("x" * 256).to_sym
    expects_logging(:warn, includes(key.to_s))

    @attributes.add(key, "")
    assert_equal 0, @attributes.length
  end

  def test_truncates_string_values
    value = "x" * 1000

    @attributes.add(:key, value)
    assert_equal 255, @attributes[:key].length
  end

  def test_truncates_symbol_values
    value = ("x" * 1000).to_sym

    @attributes.add(:key, value)
    assert_equal 255, @attributes[:key].length
  end

  def test_leaves_numbers_alone
    @attributes.add(:key, 42)
    assert_equal 42, @attributes[:key]
  end

end
