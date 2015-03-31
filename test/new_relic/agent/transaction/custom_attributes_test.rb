# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','..','test_helper'))
require 'new_relic/agent/transaction/custom_attributes'
require 'new_relic/agent/attribute_filter'

class NewRelic::Agent::Transaction
  class CustomAttributesTest < Minitest::Test

    AttributeFilter = NewRelic::Agent::AttributeFilter

    def setup
      filter = AttributeFilter.new(NewRelic::Agent.config)
      @attributes = CustomAttributes.new(filter)
    end

    def test_limits_key_length
      key = "x" * (CustomAttributes::KEY_LIMIT + 1)
      expects_logging(:warn, includes(key))

      @attributes.add(key, "")
      assert_equal 0, @attributes.length
    end

    def test_limits_key_length_symbol
      key = ("x" * (CustomAttributes::KEY_LIMIT + 1)).to_sym
      expects_logging(:warn, includes(key.to_s))

      @attributes.add(key, "")
      assert_equal 0, @attributes.length
    end

    def test_limits_key_length_on_merge
      key = ("x" * (CustomAttributes::KEY_LIMIT + 1)).to_sym
      expects_logging(:warn, includes(key.to_s))

      @attributes.merge!(key => "")
      assert_equal 0, @attributes.length
    end

    def test_truncates_string_values
      value = "x" * 1000

      @attributes.add(:key, value)
      assert_equal CustomAttributes::VALUE_LIMIT, @attributes[:key].length
    end

    def test_truncates_symbol_values
      value = ("x" * 1000).to_sym

      @attributes.add(:key, value)
      assert_equal CustomAttributes::VALUE_LIMIT, @attributes[:key].length
    end

    def test_leaves_numbers_alone
      @attributes.add(:key, 42)
      assert_equal 42, @attributes[:key]
    end

    def test_limits_attribute_count
      100.times do |i|
        @attributes.add(i.to_s, i)
      end

      assert_equal CustomAttributes::COUNT_LIMIT, @attributes.length
    end
  end
end
