# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../data_container_tests'
require 'new_relic/agent/log_event_aggregator'

module NewRelic::Agent
  class LogEventAggregatorTest < Minitest::Test
    def setup
      nr_freeze_process_time
      @aggregator = NewRelic::Agent.agent.log_event_aggregator
      @aggregator.reset!

      @enabled_config = {
        :'instrumentation.logger' => 'auto',
        LogEventAggregator::OVERALL_ENABLED_KEY => true,
        LogEventAggregator::FORWARDING_ENABLED_KEY => true
      }
      NewRelic::Agent.config.add_config_for_testing(@enabled_config)

      # Callbacks for enabled only happen on SSC addition
      NewRelic::Agent.config.notify_server_source_added

      NewRelic::Agent.instance.stats_engine.reset!
    end

    def teardown
      NewRelic::Agent.config.remove_config(@enabled_config)
    end

    CAPACITY_KEY = LogEventAggregator.capacity_key

    # Helpers for DataContainerTests

    def create_container
      @aggregator
    end

    def populate_container(container, n)
      n.times do |i|
        container.record('A log message', ::Logger::Severity.constants.sample.to_s)
      end
    end

    def common_attributes_from_melt
      @aggregator.record('Test', 'DEBUG')
      data = LogEventAggregator.payload_to_melt_format(@aggregator.harvest!)
      data[0][0][:common][:attributes]
    end

    include NewRelic::DataContainerTests

    def test_records_enabled_metrics_on_startup
      with_config(
        LogEventAggregator::OVERALL_ENABLED_KEY => true,
        LogEventAggregator::METRICS_ENABLED_KEY => true,
        LogEventAggregator::FORWARDING_ENABLED_KEY => true,
        LogEventAggregator::DECORATING_ENABLED_KEY => true
      ) do
        NewRelic::Agent.config.notify_server_source_added

        assert_metrics_recorded_exclusive({
          'Supportability/Logging/Ruby/Logger/enabled' => {:call_count => 1},
          'Supportability/Logging/Metrics/Ruby/enabled' => {:call_count => 1},
          'Supportability/Logging/Forwarding/Ruby/enabled' => {:call_count => 1},
          'Supportability/Logging/LocalDecorating/Ruby/enabled' => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_records_disabled_metrics_on_startup
      with_config(
        LogEventAggregator::OVERALL_ENABLED_KEY => false,
        LogEventAggregator::METRICS_ENABLED_KEY => false,
        LogEventAggregator::FORWARDING_ENABLED_KEY => false,
        LogEventAggregator::DECORATING_ENABLED_KEY => false
      ) do
        NewRelic::Agent.config.notify_server_source_added

        assert_metrics_recorded_exclusive({
          'Supportability/Logging/Ruby/Logger/disabled' => {:call_count => 1},
          'Supportability/Logging/Metrics/Ruby/disabled' => {:call_count => 1},
          'Supportability/Logging/Forwarding/Ruby/disabled' => {:call_count => 1},
          'Supportability/Logging/LocalDecorating/Ruby/disabled' => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_records_customer_metrics_when_enabled
      with_config(LogEventAggregator::METRICS_ENABLED_KEY => true) do
        2.times { @aggregator.record('Are you counting this?', 'DEBUG') }
        @aggregator.harvest!
      end

      assert_metrics_recorded({
        'Logging/lines' => {:call_count => 2},
        'Logging/lines/DEBUG' => {:call_count => 2}
      })
    end

    def test_doesnt_record_customer_metrics_when_overall_disabled_and_metrics_enabled
      with_config(
        LogEventAggregator::OVERALL_ENABLED_KEY => false,
        LogEventAggregator::METRICS_ENABLED_KEY => true
      ) do
        NewRelic::Agent.config.notify_server_source_added

        @aggregator.record('Are you counting this?', 'DEBUG')
        @aggregator.harvest!
      end

      assert_metrics_not_recorded([
        'Logging/lines',
        'Logging/lines/DEBUG'
      ])
    end

    def test_doesnt_record_customer_metrics_when_disabled
      with_config(LogEventAggregator::METRICS_ENABLED_KEY => false) do
        @aggregator.record('Are you counting this?', 'DEBUG')
        @aggregator.harvest!
      end

      assert_metrics_not_recorded([
        'Logging/lines',
        'Logging/lines/DEBUG'
      ])
    end

    def test_logs_with_nil_severity_use_unknown
      @aggregator.record('Chocolate chips are great', nil)
      _, events = @aggregator.harvest!

      assert_equal 'UNKNOWN', events[0][1]['level']
      assert_metrics_recorded([
        'Logging/lines/UNKNOWN'
      ])
    end

    def test_logs_with_empty_severity_use_unknown
      @aggregator.record('Chocolate chips are great', '')
      _, events = @aggregator.harvest!

      assert_equal 'UNKNOWN', events[0][1]['level']
      assert_metrics_recorded([
        'Logging/lines/UNKNOWN'
      ])
    end

    def test_does_not_record_if_overall_disabled_and_forwarding_enabled
      with_config(
        :'application_logging.enabled' => false,
        :'application_logging.forwarding.enabled' => true
      ) do
        NewRelic::Agent.config.notify_server_source_added

        @aggregator.record('Hello world!', 'DEBUG')
        _, events = @aggregator.harvest!

        assert_empty events

        assert_metrics_recorded({
          'Supportability/Logging/Ruby/Logger/disabled' => {:call_count => 1},
          'Supportability/Logging/Forwarding/Ruby/disabled' => {:call_count => 1}
        })
      end
    end

    def test_record_applies_limits
      max_samples = 100
      with_config(CAPACITY_KEY => max_samples) do
        n = max_samples + 1
        n.times do |i|
          @aggregator.record('Take it to the limit', 'FATAL')
        end

        metadata, results = @aggregator.harvest!

        assert_equal(n, metadata[:events_seen])
        assert_equal(max_samples, metadata[:reservoir_size])
        assert_equal(max_samples, results.size)
      end
    end

    def test_record_exits_if_forwarding_disabled
      with_config(LogEventAggregator::FORWARDING_ENABLED_KEY => false) do
        @aggregator.record('Speak friend and enter', 'DEBUG')
        _, results = @aggregator.harvest!

        assert_empty(results)
      end
    end

    def test_record_in_transaction
      max_samples = 100
      with_config(CAPACITY_KEY => max_samples) do
        n = max_samples + 1
        n.times do |i|
          in_transaction do
            @aggregator.record('Take it to the limit', 'FATAL')
          end
        end

        metadata, results = @aggregator.harvest!

        assert_equal(n, metadata[:events_seen])
        assert_equal(max_samples, metadata[:reservoir_size])
        assert_equal(max_samples, results.size)
      end
    end

    def test_record_in_transaction_prioritizes_sampling
      # There can be only one
      with_config(CAPACITY_KEY => 1) do
        in_transaction do |txn|
          txn.sampled = false
          @aggregator.record('Deadly', 'FATAL')
        end

        in_transaction do |txn|
          txn.sampled = true
          @aggregator.record('Buggy', 'DEBUG')
        end

        metadata, results = @aggregator.harvest!

        assert_equal(2, metadata[:events_seen])
        assert_equal(1, metadata[:reservoir_size])
        assert_equal(1, results.size)
        assert_equal('Buggy', results.first.last['message'], 'Favor sampled')
      end
    end

    def test_record_in_transaction_prioritizes
      # There can be only one
      with_config(CAPACITY_KEY => 1) do
        in_transaction do |txn|
          txn.priority = 0.5
          @aggregator.record('Deadly', 'FATAL')
        end

        in_transaction do |txn|
          txn.priority = 0.9
          @aggregator.record('Buggy', 'DEBUG')
        end

        metadata, results = @aggregator.harvest!

        assert_equal(2, metadata[:events_seen])
        assert_equal(1, metadata[:reservoir_size])
        assert_equal(1, results.size)
        assert_equal('Buggy', results.first.last['message'])
      end
    end

    def test_record_without_transaction_randomizes
      # There can be only one
      with_config(CAPACITY_KEY => 1) do
        LogPriority.stubs(:rand).returns(0.9)
        @aggregator.record('Buggy', 'DEBUG')

        LogPriority.stubs(:rand).returns(0.1)
        @aggregator.record('Deadly', 'FATAL')

        metadata, results = @aggregator.harvest!

        assert_equal(2, metadata[:events_seen])
        assert_equal(1, metadata[:reservoir_size])
        assert_equal(1, results.size)
        assert_equal('Buggy', results.first.last['message'])
      end
    end

    def test_lowering_limit_truncates_buffer
      original_count = 100
      with_config(CAPACITY_KEY => original_count) do
        original_count.times do |i|
          @aggregator.record('Truncation happens', 'WARN')
        end
      end

      smaller_count = original_count - 10
      with_config(CAPACITY_KEY => smaller_count) do
        metadata, results = @aggregator.harvest!

        assert_equal(smaller_count, metadata[:reservoir_size])
        assert_equal(original_count, metadata[:events_seen])
        assert_equal(smaller_count, results.size)
      end
    end

    def test_record_adds_timestamp
      t0 = Process.clock_gettime(Process::CLOCK_REALTIME) * 1000
      message = "Time keeps slippin' away"
      @aggregator.record(message, 'INFO')

      _, events = @aggregator.harvest!

      assert_equal(1, events.size)
      event = events.first

      assert_equal({
        'level' => 'INFO',
        'message' => message,
        'timestamp' => t0
      },
        event.last)
    end

    def test_records_metrics_on_harvest
      with_config(CAPACITY_KEY => 5) do
        9.times { @aggregator.record('Are you counting this?', 'DEBUG') }
        @aggregator.harvest!

        assert_metrics_recorded_exclusive({
          'Logging/lines' => {:call_count => 9},
          'Logging/lines/DEBUG' => {:call_count => 9},
          'Logging/Forwarding/Dropped' => {:call_count => 4},
          'Supportability/Logging/Forwarding/Seen' => {:call_count => 9},
          'Supportability/Logging/Forwarding/Sent' => {:call_count => 5}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_high_security_mode
      with_config(CAPACITY_KEY => 5, :high_security => true) do
        # We refresh the high security setting on this notification
        NewRelic::Agent.config.notify_server_source_added

        9.times { @aggregator.record('Are you counting this?', 'DEBUG') }
        _, items = @aggregator.harvest!

        # Never aggregate logs
        assert_empty items

        # We are fine to count them, though....
        assert_metrics_recorded_exclusive({
          'Logging/lines' => {:call_count => 9},
          'Logging/lines/DEBUG' => {:call_count => 9},
          'Supportability/Logging/Ruby/Logger/enabled' => {:call_count => 1},
          'Supportability/Logging/Metrics/Ruby/enabled' => {:call_count => 1},
          'Supportability/Logging/Forwarding/Ruby/enabled' => {:call_count => 1},
          'Supportability/Logging/LocalDecorating/Ruby/disabled' => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_overall_disabled
      with_config(LogEventAggregator::OVERALL_ENABLED_KEY => false) do
        # Refresh the value of @enabled on the LogEventAggregator
        NewRelic::Agent.config.notify_server_source_added

        @aggregator.record('', 'DEBUG')
        _, events = @aggregator.harvest!

        # Record no events
        assert_empty events

        # All settings should report as disabled regardless of config option
        assert_metrics_recorded_exclusive({
          'Supportability/Logging/Ruby/Logger/disabled' => {:call_count => 1},
          'Supportability/Logging/Metrics/Ruby/disabled' => {:call_count => 1},
          'Supportability/Logging/Forwarding/Ruby/disabled' => {:call_count => 1},
          'Supportability/Logging/LocalDecorating/Ruby/disabled' => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_overall_disabled_in_high_security_mode
      with_config(
        CAPACITY_KEY => 5,
        :high_security => true,
        LogEventAggregator::OVERALL_ENABLED_KEY => false
      ) do
        # We refresh the high security setting on this notification
        NewRelic::Agent.config.notify_server_source_added

        9.times { @aggregator.record('Are you counting this?', 'DEBUG') }
        _, items = @aggregator.harvest!

        # Never aggregate logs
        assert_empty items

        assert_metrics_recorded_exclusive({
          'Supportability/Logging/Ruby/Logger/disabled' => {:call_count => 1},
          'Supportability/Logging/Metrics/Ruby/disabled' => {:call_count => 1},
          'Supportability/Logging/Forwarding/Ruby/disabled' => {:call_count => 1},
          'Supportability/Logging/LocalDecorating/Ruby/disabled' => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_basic_conversion_to_melt_format
      LinkingMetadata.stubs(:append_service_linking_metadata).returns({
        'entity.guid' => 'GUID',
        'entity.name' => 'Hola'
      })

      log_data = [
        {
          events_seen: 0,
          reservoir_size: 0
        },
        [
          [{"priority": 1}, {"message": 'This is a mess'}]
        ]
      ]

      payload, size = LogEventAggregator.payload_to_melt_format(log_data)
      expected = [{
        common: {attributes: {'entity.guid' => 'GUID', 'entity.name' => 'Hola'}},
        logs: [{"message": 'This is a mess'}]
      }]

      assert_equal 1, size
      assert_equal expected, payload
    end

    def test_create_event_truncates_message_when_exceeding_max_bytes
      right_size_message = String.new('a' * LogEventAggregator::MAX_BYTES)
      message = right_size_message + 'b'
      event = @aggregator.create_event(1, message, 'INFO')

      assert_equal(right_size_message, event[1]['message'])
    end

    def test_create_event_doesnt_truncate_message_when_at_max_bytes
      message = String.new('a' * LogEventAggregator::MAX_BYTES)
      event = @aggregator.create_event(1, message, 'INFO')

      assert_equal(message, event[1]['message'])
    end

    def test_create_event_doesnt_truncate_message_when_below_max_bytes
      message = String.new('a' * (LogEventAggregator::MAX_BYTES - 1))
      event = @aggregator.create_event(1, message, 'INFO')

      assert_equal(message, event[1]['message'])
    end

    def test_does_not_record_if_message_is_nil
      @aggregator.record(nil, 'DEBUG')
      _, events = @aggregator.harvest!

      assert_empty events
    end

    def test_does_not_record_if_message_empty_string
      @aggregator.record('', 'DEBUG')
      _, events = @aggregator.harvest!

      assert_empty events
    end

    def test_sets_minimum_log_level_to_debug_when_not_within_default_severities
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'milkshake') do
        assert_equal :DEBUG, @aggregator.send(:minimum_log_level)
      end
    end

    def test_logs_error_when_log_level_not_within_default_severities
      logger = MiniTest::Mock.new
      logger.expect :log_once, nil, [:error, /Invalid application_logging.forwarding.log_level/]

      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'milkshake') do
        NewRelic::Agent.stub :logger, logger do
          @aggregator.send(:minimum_log_level)
          logger.verify
        end
      end
    end

    def test_sets_log_level_constant_to_symbolized_capitalized_level
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'info') do
        assert_equal :INFO, @aggregator.send(:configured_log_level_constant)
      end
    end

    def test_sets_minimum_log_level_when_config_capitalized
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'INFO') do
        assert_equal(:INFO, @aggregator.send(:minimum_log_level))
      end
    end

    def test_does_not_record_log_events_with_a_severity_below_config
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'info') do
        assert_equal :INFO, @aggregator.send(:configured_log_level_constant)

        @aggregator.record('Debug log', 'debug')
        _, events = @aggregator.harvest!

        assert_empty events
      end
    end

    def test_records_log_events_with_severity_matching_config
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'info') do
        assert_equal :INFO, @aggregator.send(:configured_log_level_constant)

        log_message = 'Info log'
        @aggregator.record(log_message, 'info')
        _, events = @aggregator.harvest!

        assert_equal(log_message, events.first.last['message'])
      end
    end

    def test_records_log_events_with_severity_higher_than_config
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'info') do
        assert_equal :INFO, @aggregator.send(:configured_log_level_constant)

        log_message = 'Warn log'
        @aggregator.record(log_message, 'warn')
        _, events = @aggregator.harvest!

        assert_equal(log_message, events.first.last['message'])
      end
    end

    def test_records_log_events_not_within_default_severities
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'info') do
        assert_equal :INFO, @aggregator.send(:configured_log_level_constant)

        log_message = 'Vanilla'
        @aggregator.record(log_message, 'milkshake')
        _, events = @aggregator.harvest!

        assert_equal(log_message, events.first.last['message'])
      end
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
        LogEventAggregator.stub_const(:MAX_ATTRIBUTE_COUNT, 1) do
          NewRelic::Agent.add_custom_log_attributes('snack' => 'Ritz and cheese')
          NewRelic::Agent.add_custom_log_attributes('lunch' => 'Cold pizza')

          logger.verify

          assert(@aggregator.already_warned_custom_attribute_count_limit)
          assert_equal(1, @aggregator.custom_attributes.size)
        end
      end
    end

    def test_log_attrs_returns_early_if_already_warned
      @aggregator.instance_variable_set(:@already_warned_custom_attribute_count_limit, true)
      NewRelic::Agent.add_custom_log_attributes('dinner' => 'Lasagna')
    end

    def test_add_log_attrs_doesnt_warn_twice
      logger = MiniTest::Mock.new
      logger.expect :warn, [], [/Too many custom/]

      NewRelic::Agent.stub :logger, logger do
        LogEventAggregator.stub_const(:MAX_ATTRIBUTE_COUNT, 1) do
          @aggregator.stub :already_warned_custom_attribute_count_limit, true do
            NewRelic::Agent.add_custom_log_attributes(dinner: 'Lasagna')
            assert_raises(MockExpectationError) { logger.verify }
          end
        end
      end
    end

    def test_add_log_attrs_limits_attr_key_length
      LogEventAggregator.stub_const(:ATTRIBUTE_KEY_CHARACTER_LIMIT, 2) do
        NewRelic::Agent.add_custom_log_attributes('mount' => 'rainier')

        assert_includes(common_attributes_from_melt, 'mo')
      end
    end

    def test_add_log_attrs_limits_attr_value_length
      LogEventAggregator.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 4) do
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
        LogEventAggregator.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 2) do
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
        LogEventAggregator.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 2) do
          key = :key
          value = 2.22
          NewRelic::Agent.add_custom_log_attributes(key => value)

          refute_includes(common_attributes_from_melt, key)
          logger.verify
        end
      end
    end

    def test_truncates_too_long_symbol_as_string
      LogEventAggregator.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 2) do
        key = 'key'
        value = :value
        NewRelic::Agent.add_custom_log_attributes(key => value)
        common_attributes = common_attributes_from_melt

        assert_includes(common_attributes, key)
        assert_equal(LogEventAggregator::ATTRIBUTE_VALUE_CHARACTER_LIMIT, common_attributes[key].length)
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
      LogEventAggregator.stub_const(:ATTRIBUTE_VALUE_CHARACTER_LIMIT, 5) do
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
