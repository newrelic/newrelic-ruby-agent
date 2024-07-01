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
        :'instrumentation.logstasher' => 'auto',
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
          'Supportability/Logging/Ruby/LogStasher/enabled' => {:call_count => 1},
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
          'Supportability/Logging/Ruby/LogStasher/disabled' => {:call_count => 1},
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
          'Supportability/Logging/Ruby/LogStasher/enabled' => {:call_count => 1},
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
          'Supportability/Logging/Ruby/LogStasher/disabled' => {:call_count => 1},
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
          'Supportability/Logging/Ruby/LogStasher/disabled' => {:call_count => 1},
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
      # NOTE: a default string value is applied by the allowlist in the
      #       DefaultSource hash which is then converted to an upcased symbol
      #       via `configured_log_level_constant`.
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'milkshake') do
        assert_equal :DEBUG, @aggregator.send(:configured_log_level_constant)
      end
    end

    def test_sets_log_level_constant_to_symbolized_capitalized_level
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'info') do
        assert_equal :INFO, @aggregator.send(:configured_log_level_constant)
      end
    end

    def test_sets_minimum_log_level_when_config_capitalized
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'INFO') do
        assert_equal(:INFO, @aggregator.send(:configured_log_level_constant))
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

    def test_record_json_sets_severity_when_given_level
      @aggregator.record_logstasher_event({'level' => :warn, 'message' => 'yikes!'})
      _, events = @aggregator.harvest!

      assert_equal 'WARN', events[0][1]['level']
      assert_metrics_recorded([
        'Logging/lines/WARN'
      ])
    end

    def test_record_json_sets_severity_unknown_when_no_level
      @aggregator.record_logstasher_event({'message' => 'hello there'})
      _, events = @aggregator.harvest!

      assert_equal 'UNKNOWN', events[0][1]['level']
      assert_metrics_recorded([
        'Logging/lines/UNKNOWN'
      ])
    end

    def test_record_json_does_not_record_if_message_is_nil
      @aggregator.record_logstasher_event({'level' => :info, 'message' => nil})
      _, events = @aggregator.harvest!

      assert_empty events
    end

    def test_record_json_does_not_record_if_message_empty_string
      @aggregator.record_logstasher_event({'level' => :info, 'message' => ''})
      _, events = @aggregator.harvest!

      assert_empty events
    end

    def test_record_json_returns_message_when_avaliable
      @aggregator.record_logstasher_event({'level' => :warn, 'message' => 'A trex is near'})
      _, events = @aggregator.harvest!

      assert_equal 'A trex is near', events[0][1]['message']
    end

    def test_create_logstasher_event_do_not_message_when_not_given
      @aggregator.record_logstasher_event({'level' => :info})
      _, events = @aggregator.harvest!

      refute events[0][1]['message']
    end

    def test_add_json_event_attributes_records_attributes
      @aggregator.record_logstasher_event({'source' => '127.0.0.1', 'tags' => ['log']})
      _, events = @aggregator.harvest!

      assert_includes(events[0][1]['attributes'], 'source')
      assert_includes(events[0][1]['attributes'], 'tags')
    end

    def test_add_json_event_attributes_deletes_already_recorded_attributes
      @aggregator.record_logstasher_event({'message' => 'bye', 'level' => :info, '@timestamp' => 'now'})
      _, events = @aggregator.harvest!

      refute_includes(events[0][1]['attributes'], 'message')
      refute_includes(events[0][1]['attributes'], 'level')
      refute_includes(events[0][1]['attributes'], '@timestamp')
    end

    def test_logstasher_forwarding_disabled_and_high_security_enabled
      with_config(:'application_logging.forwarding.enabled' => false) do
        # Refresh the high security setting on this notification
        NewRelic::Agent.config.notify_server_source_added

        @aggregator.record_logstasher_event({'message' => 'high security enabled', 'level' => :info})
        _, events = @aggregator.harvest!

        assert_empty events
      end
    end

    def test_records_customer_metrics_when_enabled_logstasher
      with_config(LogEventAggregator::METRICS_ENABLED_KEY => true) do
        2.times { @aggregator.record_logstasher_event({'message' => 'metrics enabled', 'level' => :debug}) }
        @aggregator.harvest!
      end

      assert_metrics_recorded({
        'Logging/lines' => {:call_count => 2},
        'Logging/lines/DEBUG' => {:call_count => 2}
      })
    end

    def test_doesnt_record_customer_metrics_when_overall_disabled_and_metrics_enabled_logstasher
      with_config(
        LogEventAggregator::OVERALL_ENABLED_KEY => false,
        LogEventAggregator::METRICS_ENABLED_KEY => true
      ) do
        NewRelic::Agent.config.notify_server_source_added

        @aggregator.record_logstasher_event({'message' => 'overall disabled, metrics enabled', 'level' => :debug})
        @aggregator.harvest!
      end

      assert_metrics_not_recorded([
        'Logging/lines',
        'Logging/lines/DEBUG'
      ])
    end

    def test_doesnt_record_customer_metrics_when_disabled_logstasher
      with_config(LogEventAggregator::METRICS_ENABLED_KEY => false) do
        @aggregator.record_logstasher_event({'message' => 'metrics disabled', 'level' => :warn})
        @aggregator.harvest!
      end

      assert_metrics_not_recorded([
        'Logging/lines',
        'Logging/lines/WARN'
      ])
    end

    def test_high_security_mode_logstasher
      with_config(CAPACITY_KEY => 5, :high_security => true) do
        # Refresh the high security setting on this notification
        NewRelic::Agent.config.notify_server_source_added

        @aggregator.record_logstasher_event({'message' => 'high security enabled', 'level' => :info})
        _, events = @aggregator.harvest!

        assert_empty events
      end
    end

    def test_does_not_record_logstasher_events_with_a_severity_below_config
      with_config(LogEventAggregator::LOG_LEVEL_KEY => 'info') do
        assert_equal :INFO, @aggregator.send(:configured_log_level_constant)

        @aggregator.record_logstasher_event({'message' => 'severity below config', 'level' => :debug})
        _, events = @aggregator.harvest!

        assert_empty events
      end
    end

    def test_record_logstasher_exits_if_forwarding_disabled
      with_config(LogEventAggregator::FORWARDING_ENABLED_KEY => false) do
        @aggregator.record_logstasher_event({'message' => 'forwarding disabled', 'level' => :info})
        _, results = @aggregator.harvest!

        assert_empty results
      end
    end

    def test_nil_when_record_logstasher_errors
      @aggregator.stub(:severity_too_low?, -> { raise 'kaboom' }) do
        @aggregator.record_logstasher_event({'level' => :warn, 'message' => 'A trex is near'})
        _, results = @aggregator.harvest!

        assert_empty results
      end
    end
  end
end
