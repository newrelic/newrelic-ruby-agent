# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'data_container_tests'))

require 'new_relic/agent/log_event_aggregator'

module NewRelic::Agent
  class LogEventAggregatorTest < Minitest::Test
    def setup
      nr_freeze_process_time
      @aggregator = NewRelic::Agent.agent.log_event_aggregator
      @aggregator.reset!

      @enabled_config = {LogEventAggregator::FORWARDING_ENABLED_KEY => true}
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
        container.record("A log message", ::Logger::Severity.constants.sample.to_s)
      end
    end

    include NewRelic::DataContainerTests

    def test_records_enabled_metrics_on_startup
      with_config(
        LogEventAggregator::METRICS_ENABLED_KEY => true,
        LogEventAggregator::FORWARDING_ENABLED_KEY => true,
        LogEventAggregator::DECORATING_ENABLED_KEY => true
      ) do
        NewRelic::Agent.config.notify_server_source_added

        assert_metrics_recorded_exclusive({
          "Supportability/Logging/Metrics/Ruby/enabled" => {:call_count => 1},
          "Supportability/Logging/Forwarding/Ruby/enabled" => {:call_count => 1},
          "Supportability/Logging/LocalDecorating/Ruby/enabled" => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_records_disabled_metrics_on_startup
      with_config(
        LogEventAggregator::METRICS_ENABLED_KEY => false,
        LogEventAggregator::FORWARDING_ENABLED_KEY => false,
        LogEventAggregator::DECORATING_ENABLED_KEY => false
      ) do
        NewRelic::Agent.config.notify_server_source_added

        assert_metrics_recorded_exclusive({
          "Supportability/Logging/Metrics/Ruby/disabled" => {:call_count => 1},
          "Supportability/Logging/Forwarding/Ruby/disabled" => {:call_count => 1},
          "Supportability/Logging/LocalDecorating/Ruby/disabled" => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_records_customer_metrics_when_enabled
      with_config LogEventAggregator::METRICS_ENABLED_KEY => true do
        2.times { @aggregator.record("Are you counting this?", "DEBUG") }
        @aggregator.harvest!
      end

      assert_metrics_recorded({
        "Logging/lines" => {:call_count => 2},
        "Logging/lines/DEBUG" => {:call_count => 2}
      })
    end

    def test_doesnt_record_customer_metrics_when_disabled
      with_config LogEventAggregator::METRICS_ENABLED_KEY => false do
        2.times { @aggregator.record("Are you counting this?", "DEBUG") }
        @aggregator.harvest!
      end

      assert_metrics_not_recorded([
        "Logging/lines",
        "Logging/lines/DEBUG"
      ])
    end

    def test_record_by_default_limit
      max_samples = NewRelic::Agent.config[CAPACITY_KEY]
      n = max_samples + 1
      n.times do |i|
        @aggregator.record("Take it to the limit", "FATAL")
      end

      metadata, results = @aggregator.harvest!
      assert_equal(n, metadata[:events_seen])
      assert_equal(max_samples, metadata[:reservoir_size])
      assert_equal(max_samples, results.size)
    end

    def test_record_in_transaction
      max_samples = NewRelic::Agent.config[CAPACITY_KEY]
      n = max_samples + 1
      n.times do |i|
        in_transaction do
          @aggregator.record("Take it to the limit", "FATAL")
        end
      end

      metadata, results = @aggregator.harvest!
      assert_equal(n, metadata[:events_seen])
      assert_equal(max_samples, metadata[:reservoir_size])
      assert_equal(max_samples, results.size)
    end

    def test_record_in_transaction_prioritizes_sampling
      # There can be only one
      with_config(CAPACITY_KEY => 1) do
        in_transaction do |txn|
          txn.sampled = false
          @aggregator.record("Deadly", "FATAL")
        end

        in_transaction do |txn|
          txn.sampled = true
          @aggregator.record("Buggy", "DEBUG")
        end

        metadata, results = @aggregator.harvest!

        assert_equal(2, metadata[:events_seen])
        assert_equal(1, metadata[:reservoir_size])
        assert_equal(1, results.size)
        assert_equal("Buggy", results.first.last["message"], "Favor sampled")
      end
    end

    def test_record_in_transaction_prioritizes
      # There can be only one
      with_config(CAPACITY_KEY => 1) do
        in_transaction do |txn|
          txn.priority = 0.5
          @aggregator.record("Deadly", "FATAL")
        end

        in_transaction do |txn|
          txn.priority = 0.9
          @aggregator.record("Buggy", "DEBUG")
        end

        metadata, results = @aggregator.harvest!

        assert_equal(2, metadata[:events_seen])
        assert_equal(1, metadata[:reservoir_size])
        assert_equal(1, results.size)
        assert_equal("Buggy", results.first.last["message"])
      end
    end

    def test_record_without_transaction_randomizes
      # There can be only one
      with_config(CAPACITY_KEY => 1) do
        LogPriority.stubs(:rand).returns(0.9)
        @aggregator.record("Buggy", "DEBUG")

        LogPriority.stubs(:rand).returns(0.1)
        @aggregator.record("Deadly", "FATAL")

        metadata, results = @aggregator.harvest!

        assert_equal(2, metadata[:events_seen])
        assert_equal(1, metadata[:reservoir_size])
        assert_equal(1, results.size)
        assert_equal("Buggy", results.first.last["message"])
      end
    end

    def test_lowering_limit_truncates_buffer
      orig_max_samples = NewRelic::Agent.config[CAPACITY_KEY]

      orig_max_samples.times do |i|
        @aggregator.record("Truncation happens", "WARN")
      end

      new_max_samples = orig_max_samples - 10
      with_config(CAPACITY_KEY => new_max_samples) do
        metadata, results = @aggregator.harvest!
        assert_equal(new_max_samples, metadata[:reservoir_size])
        assert_equal(orig_max_samples, metadata[:events_seen])
        assert_equal(new_max_samples, results.size)
      end
    end

    def test_record_adds_timestamp
      t0 = Process.clock_gettime(Process::CLOCK_REALTIME) * 1000
      message = "Time keeps slippin' away"
      @aggregator.record(message, "INFO")

      _, events = @aggregator.harvest!

      assert_equal(1, events.size)
      event = events.first

      assert_equal({
        'level' => "INFO",
        'message' => message,
        'timestamp' => t0
      },
        event.last)
    end

    def test_records_metrics_on_harvest
      with_config CAPACITY_KEY => 5 do
        9.times { @aggregator.record("Are you counting this?", "DEBUG") }
        @aggregator.harvest!

        assert_metrics_recorded_exclusive({
          "Logging/lines" => {:call_count => 9},
          "Logging/lines/DEBUG" => {:call_count => 9},
          "Logging/Forwarding/Dropped" => {:call_count => 4},
          "Supportability/Logging/Forwarding/Seen" => {:call_count => 9},
          "Supportability/Logging/Forwarding/Sent" => {:call_count => 5}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_high_security_mode
      with_config CAPACITY_KEY => 5, :high_security => true do
        # We refresh the high security setting on this notification
        NewRelic::Agent.config.notify_server_source_added

        9.times { @aggregator.record("Are you counting this?", "DEBUG") }
        _, items = @aggregator.harvest!

        # Never aggregate logs
        assert_empty items

        # We are fine to count them, though....
        assert_metrics_recorded_exclusive({
          "Logging/lines" => {:call_count => 9},
          "Logging/lines/DEBUG" => {:call_count => 9},
          "Supportability/Logging/Metrics/Ruby/enabled" => {:call_count => 1}
          "Supportability/Logging/Forwarding/Ruby/enabled" => {:call_count => 1},
          "Supportability/Logging/LocalDecorating/Ruby/disabled" => {:call_count => 1}
        },
          :ignore_filter => %r{^Supportability/API/})
      end
    end

    def test_basic_conversion_to_melt_format
      LinkingMetadata.stubs(:append_service_linking_metadata).returns({
        "entity.guid" => "GUID",
        "entity.name" => "Hola"
      })

      log_data = [
        {
          events_seen: 0,
          reservoir_size: 0
        },
        [
          [{"priority": 1}, {"message": "This is a mess"}]
        ]
      ]

      payload, size = LogEventAggregator.payload_to_melt_format(log_data)
      expected = [{
        common: {attributes: {"entity.guid" => "GUID"}},
        logs: [{"message": "This is a mess"}]
      }]

      assert_equal 1, size
      assert_equal expected, payload
    end
  end
end
