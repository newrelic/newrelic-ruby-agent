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
    end

    def common_attributes_from_melt
      @aggregator.record('Test', 'DEBUG')
      data = LogEventAggregator.payload_to_melt_format(@aggregator.harvest!)
      data[0][0][:common][:attributes]
    end

    def test_add_log_attrs_puts_customer_attributes_in_common
      NewRelic::Agent.add_custom_log_attributes(snack: 'Ritz and cheese')

      assert_includes(common_attributes_from_melt['snack'], 'Ritz and cheese')
    end

    def test_add_log_attrs_adds_attrs_from_multiple_calls
      NewRelic::Agent.add_custom_log_attributes(snack: 'Ritz and cheese')
      NewRelic::Agent.add_custom_log_attributes(lunch: 'Cold pizza')

      assert_includes(common_attributes_from_melt['snack'], 'Ritz and cheese')
      assert_includes(common_attributes_from_melt['lunch'], 'Cold pizza')
    end

    def test_add_log_attrs_overrides_value_with_second_call
      NewRelic::Agent.add_custom_log_attributes(snack: 'Ritz and cheese')
      NewRelic::Agent.add_custom_log_attributes(snack: 'Cold pizza')

      assert_includes(common_attributes_from_melt['snack'], 'Cold pizza')
    end

    def test_add_log_attrs_limits_attrs
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Too many custom/]

      NewRelic::Agent.stub :logger, logger do
        LogEventAttributes.stub_const(:MAX_ATTRIBUTE_COUNT, 1) do
          NewRelic::Agent.add_custom_log_attributes('snack' => 'Ritz and cheese')
          NewRelic::Agent.add_custom_log_attributes('lunch' => 'Cold pizza')

          logger.verify

          assert(@aggregator.attributes.already_warned_custom_attribute_count_limit)
          assert_equal(1, @aggregator.attributes.custom_attributes.size)
        end
      end
    end

    def test_log_attrs_returns_early_if_already_warned
      @aggregator.attributes.instance_variable_set(:@already_warned_custom_attribute_count_limit, true)
      NewRelic::Agent.add_custom_log_attributes('dinner' => 'Lasagna')
    end

    def test_add_log_attrs_doesnt_warn_twice
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Too many custom/]

      NewRelic::Agent.stub :logger, logger do
        LogEventAttributes.stub_const(:MAX_ATTRIBUTE_COUNT, 1) do
          @aggregator.attributes.stub :already_warned_custom_attribute_count_limit, true do
            NewRelic::Agent.add_custom_log_attributes(dinner: 'Lasagna')
            assert_raises(MockExpectationError) { logger.verify }
          end
        end
      end
    end

    def test_add_log_attrs_limits_attr_key_length
      LogEventAttributes.stub_const(:ATTRIBUTE_KEY_CHARACTER_LIMIT, 2) do
        NewRelic::Agent.add_custom_log_attributes('mount' => 'rainier')

        assert_includes(common_attributes_from_melt, 'mo')
      end
    end

    def test_add_log_attrs_limits_attr_value_length
      LogEventAttributes.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 4) do
        NewRelic::Agent.add_custom_log_attributes('mount' => 'rainier')

        assert_includes(common_attributes_from_melt['mount'], 'rain')
      end
    end

    def test_add_log_attrs_coerces_all_keys_to_string
      key_1 = :snack
      key_2 = 123
      key_3 = 3.14

      NewRelic::Agent.add_custom_log_attributes(key_1 => 'Attr 1')
      NewRelic::Agent.add_custom_log_attributes(key_2 => 'Attr 2')
      NewRelic::Agent.add_custom_log_attributes(key_3 => 'Attr 3')

      common_attrs = common_attributes_from_melt

      assert_includes(common_attrs, key_1.to_s)
      assert_includes(common_attrs, key_2.to_s)
      assert_includes(common_attrs, key_3.to_s)
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
        assert_equal(LogEventAttributes::ATTRIBUTE_VALUE_CHARACTER_LIMIT, common_attributes[key].length)
        assert_kind_of(String, common_attributes[key])
      end
    end

    def test_log_attr_nil_key_drops_attribute
      NewRelic::Agent.add_custom_log_attributes(nil => 'hi')

      refute_includes(common_attributes_from_melt, nil)
      refute_includes(common_attributes_from_melt, '')
    end

    def test_log_attr_nil_value_drops_attribute
      NewRelic::Agent.add_custom_log_attributes('hi' => nil)

      refute_includes(common_attributes_from_melt, ['hi'], nil)
    end

    def test_log_attr_empty_string_drops_attribute
      NewRelic::Agent.add_custom_log_attributes('' => '?')

      refute_includes(common_attributes_from_melt, nil)
      refute_includes(common_attributes_from_melt, '')
    end

    def test_does_not_truncate_if_under_or_equal_to_limit
      LogEventAttributes.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 5) do
        key = 'key'
        values = [12, true, 2.0, 'hi', :hello]

        values.each do |value|
          NewRelic::Agent.add_custom_log_attributes(key => value)
          common_attributes = common_attributes_from_melt

          assert_equal(common_attributes[key], value)
        end
      end
    end
  end
end
