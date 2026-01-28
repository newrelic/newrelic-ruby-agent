# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class LoggingInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  def setup
    @written = StringIO.new

    @appender = Logging.appenders.io('test_appender', @written)
    @logger = Logging.logger('test_logger')
    Logging.init :debug, :info, :custom_level_meow, :warn, :error, :fatal
    @logger.level = :debug
    @logger.add_appenders(@appender)

    @aggregator = NewRelic::Agent.agent.log_event_aggregator
    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def test_no_instrumentation_when_disabled
    with_config(:'instrumentation.logging' => 'disabled') do
      @logger.info 'Test message'
    end
    _, events = @aggregator.harvest!

    assert_empty(events)
  end

  def test_level_is_recorded
    in_transaction do
      @logger.info 'Test message'
    end
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_metrics_recorded(%w[Logging/lines/INFO])
  end

  def test_log_levels_are_recorded
    in_transaction do
      @logger.debug 'Debug message'
      @logger.info 'Info message'
      @logger.warn 'Warning message'
      @logger.error 'Error message'
      @logger.fatal 'Fatal message'
    end
    _, events = @aggregator.harvest!

    assert_equal 'DEBUG', events[0][1]['level']
    assert_equal 'INFO', events[1][1]['level']
    assert_equal 'WARN', events[2][1]['level']
    assert_equal 'ERROR', events[3][1]['level']
    assert_equal 'FATAL', events[4][1]['level']
    assert_metrics_recorded(%w[Logging/lines/DEBUG])
    assert_metrics_recorded(%w[Logging/lines/INFO])
    assert_metrics_recorded(%w[Logging/lines/WARN])
    assert_metrics_recorded(%w[Logging/lines/ERROR])
    assert_metrics_recorded(%w[Logging/lines/FATAL])
  end

  def test_custom_log_level_is_recorded
    in_transaction do
      @logger.custom_level_meow 'Cats are purrfect!'
    end
    _, events = @aggregator.harvest!

    assert_equal 'CUSTOM_LEVEL_MEOW', events[0][1]['level']
    assert_equal 'Cats are purrfect!', events[0][1]['message']
    assert_metrics_recorded(%w[Logging/lines/CUSTOM_LEVEL_MEOW])
  end

  def test_logging_attributes_are_recorded
    in_transaction do
      @logger.info 'Test message'
    end
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_equal 'test_logger', events[0][1]['logger']
    assert_equal 1, events[0][1]['level_number']
  end

  def test_logs_without_messages_are_not_recorded
    in_transaction do
      @logger.info
    end
    _, events = @aggregator.harvest!

    assert events.empty?
  end

  def test_logs_with_empty_messages_are_not_recorded
    in_transaction do
      @logger.info ''
    end
    _, events = @aggregator.harvest!

    assert events.empty?
  end

  def test_logging_events_include_trace_linkng_metadata
      in_transaction do
        @logger.info 'Test message'
      end
      _, events = @aggregator.harvest!

      assert events[0][1]['trace.id']
      assert events[0][1]['span.id']
  end

  def test_log_decorating_enabled_records_linking_metadata
    with_config(:'application_logging.local_decorating.enabled' => true) do
      in_transaction do
        @logger.info 'Decorate me!'
      end
    end

    log_output = @written.string

    assert_match(/Decorate me!/, log_output)
    assert_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end

  def test_log_decorating_enabled_records_linking_metadata
    with_config(:'application_logging.local_decorating.enabled' => false) do
      in_transaction do
        @logger.info 'Decorate me!'
      end
    end

    log_output = @written.string

    assert_match(/Decorate me!/, log_output)
    refute_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end
end
