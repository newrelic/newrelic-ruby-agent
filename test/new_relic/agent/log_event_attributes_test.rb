# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/log_event_attributes'

module NewRelic::Agent
  class LogEventAttributesTest < Minitest::Test
    def setup
      @aggregator = NewRelic::Agent.agent.log_event_aggregator
      @aggregator.reset!

     %i[@custom_attributes @custom_attribute_limit_reached].each do |attr|
        if @aggregator.attributes.instance_variable_defined?(attr)
          @aggregator.attributes.remove_instance_variable(attr)
        end
      end
    end

    def common_attributes_from_melt
      @aggregator.record('Food', 'INFO')
      data = LogEventAggregator.payload_to_melt_format(@aggregator.harvest!)
      data[0][0][:common][:attributes]
    end

    def test_add_log_attrs_puts_customer_attributes_in_common
      NewRelic::Agent.add_custom_log_attributes(snack: "Ritz and Beecher's")

      assert_includes(common_attributes_from_melt['snack'], "Ritz and Beecher's")
    end

    def test_add_log_attrs_adds_attrs_from_multiple_calls
      NewRelic::Agent.add_custom_log_attributes(snack: "Ritz and Beecher's")
      NewRelic::Agent.add_custom_log_attributes(lunch: 'Cold pizza')

      assert_includes(common_attributes_from_melt['snack'], "Ritz and Beecher's")
      assert_includes(common_attributes_from_melt['lunch'], 'Cold pizza')
    end

    def test_add_log_attrs_overrides_value_with_second_call
      NewRelic::Agent.add_custom_log_attributes(snack: "Ritz and Beecher's")
      NewRelic::Agent.add_custom_log_attributes(snack: 'Cold pizza')

      assert_includes(common_attributes_from_melt['snack'], 'Cold pizza')
    end

    def test_add_log_attrs_limits_attrs
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Too many custom/]

      NewRelic::Agent.stub :logger, logger do
        LogEventAttributes.stub_const(:MAX_ATTRIBUTE_COUNT, 1) do
          NewRelic::Agent.add_custom_log_attributes('snack' => "Ritz and Beecher's")
          NewRelic::Agent.add_custom_log_attributes('lunch' => 'Cold pizza')

          logger.verify

          assert(
            @aggregator.attributes.instance_variable_get(
              :@custom_attribute_limit_reached
            )
          )
          assert_equal(1, @aggregator.attributes.custom_attributes.size)
        end
      end
    end

    def test_log_attrs_returns_early_if_already_warned
      @aggregator.attributes.instance_variable_set(
        :@custom_attribute_limit_reached, true
      )
      NewRelic::Agent.add_custom_log_attributes('dinner' => 'Lasagna')

      assert_empty(@aggregator.attributes.custom_attributes)
    end

    def test_add_log_attrs_doesnt_warn_twice
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Too many custom/]

      NewRelic::Agent.stub :logger, logger do
        LogEventAttributes.stub_const(:MAX_ATTRIBUTE_COUNT, 1) do
          @aggregator.attributes.instance_variable_set(
            :@custom_attribute_limit_reached, true
          )
          NewRelic::Agent.add_custom_log_attributes(dinner: 'Lasagna')

          assert_raises(MockExpectationError) { logger.verify }
        end
      end
    end

    def test_add_log_attrs_limits_attr_key_length
      LogEventAttributes.stub_const(:ATTRIBUTE_KEY_CHARACTER_LIMIT, 2) do
        NewRelic::Agent.add_custom_log_attributes('dessert' => 'Tillamook')

        assert_includes(common_attributes_from_melt, 'de')
      end
    end

    def test_add_log_attrs_limits_attr_value_length
      LogEventAttributes.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 4) do
        NewRelic::Agent.add_custom_log_attributes('dessert' => 'Tillamook')

        assert_includes(common_attributes_from_melt['dessert'], 'Till')
      end
    end

    def test_add_log_attrs_coerces_all_keys_to_string
      keys = [:snack, 123, 3.14]
      keys.each { |key| NewRelic::Agent.add_custom_log_attributes(key => 'value') }
      common_attrs = common_attributes_from_melt

      keys.each { |key| assert_includes(common_attrs, key.to_s) }
    end

    def test_logs_warning_for_too_long_integer
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Can't truncate/]

      NewRelic::Agent.stub :logger, logger do
        LogEventAttributes.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 2) do
          key = :key
          value = 222
          NewRelic::Agent.add_custom_log_attributes(key => value)

          refute_includes(common_attributes_from_melt, key)
          logger.verify
        end
      end
    end

    def test_logs_warning_for_too_long_float
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Can't truncate/]

      NewRelic::Agent.stub :logger, logger do
        LogEventAttributes.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 2) do
          key = :key
          value = 2.22
          NewRelic::Agent.add_custom_log_attributes(key => value)

          refute_includes(common_attributes_from_melt, key)
          logger.verify
        end
      end
    end

    def test_truncates_too_long_symbol_as_string
      LogEventAttributes.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 2) do
        key = 'key'
        value = :value
        NewRelic::Agent.add_custom_log_attributes(key => value)
        common_attributes = common_attributes_from_melt

        assert_includes(common_attributes, key)
        assert_equal(
          LogEventAttributes::ATTRIBUTE_VALUE_CHARACTER_LIMIT,
          common_attributes[key].length
        )
        assert_kind_of(String, common_attributes[key])
      end
    end

    def test_log_attr_nil_key_drops_attribute
      NewRelic::Agent.add_custom_log_attributes(nil => 'ollie ollie oxen free')

      refute_includes(common_attributes_from_melt, nil)
      refute_includes(common_attributes_from_melt, '')
    end

    def test_log_attr_nil_value_drops_attribute
      key = 'key'
      NewRelic::Agent.add_custom_log_attributes(key => nil)

      refute_includes(common_attributes_from_melt, key)
    end

    def test_log_attr_empty_string_drops_attribute
      NewRelic::Agent.add_custom_log_attributes('' => '?')

      refute_includes(common_attributes_from_melt, nil)
      refute_includes(common_attributes_from_melt, '')
    end

    def test_does_not_truncate_if_under_or_equal_to_limit
      LogEventAttributes.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 5) do
        key = 'key'
        values = [12, true, false, 2.0, 'hej', :hallo]

        values.each do |value|
          NewRelic::Agent.add_custom_log_attributes(key => value)
          common_attributes = common_attributes_from_melt

          assert_equal(common_attributes[key], value)
        end
      end
    end

    def test_drops_attribute_pair_if_invalid_value_class
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Invalid type/]

      NewRelic::Agent.stub :logger, logger do
        key = 'key'
        value = [1, 2]
        NewRelic::Agent.add_custom_log_attributes(key => value)

        refute_includes(common_attributes_from_melt, key)
        logger.verify
      end
    end
  end
end
