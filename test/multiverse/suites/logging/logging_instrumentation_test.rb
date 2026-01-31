# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class LoggingInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  def setup
    @logger = Logging.logger('test_logger')
    Logging.init(:debug, :info, :custom_level_meow, :warn, :error, :fatal)
    @logger.level = :debug

    @aggregator = NewRelic::Agent.agent.log_event_aggregator
    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def teardown
    FileUtils.rm_f('test_logger')

    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def setup_string_appender
    @written = StringIO.new
    @appender = Logging.appenders.io('test_appender', @written)
    @logger.add_appenders(@appender)
  end

  def log_from_this_method
    @logger.info('Message with caller info')
  end

  def test_no_instrumentation_when_disabled
    with_config(:'instrumentation.logging' => 'disabled') do
      @logger.info('Test message')
    end
    _, events = @aggregator.harvest!

    assert_empty(events)
  end

  def test_level_is_recorded
    in_transaction do
      @logger.info('Test message')
    end
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_metrics_recorded(%w[Logging/lines/INFO])
  end

  def test_log_levels_are_recorded
    in_transaction do
      @logger.debug('Debug message')
      @logger.info('Info message')
      @logger.warn('Warning message')
      @logger.error('Error message')
      @logger.fatal('Fatal message')
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
      @logger.custom_level_meow('Cats are purrfect!')
    end
    _, events = @aggregator.harvest!

    assert_equal 'CUSTOM_LEVEL_MEOW', events[0][1]['level']
    assert_equal 'Cats are purrfect!', events[0][1]['message']
    assert_metrics_recorded(%w[Logging/lines/CUSTOM_LEVEL_MEOW])
  end

  def test_logging_attributes_are_recorded
    in_transaction do
      @logger.info('Test message')
    end
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_equal 'test_logger', events[0][1]['logger']
    assert_equal 1, events[0][1]['level_number']
  end

  def test_captures_caller_tracing_attributes_when_enabled
    @logger.caller_tracing = true

    in_transaction do
      log_from_this_method
    end
    _, events = @aggregator.harvest!

    assert_equal 1, events.length
    event_attributes = events[0][1]

    assert event_attributes['file']
    assert event_attributes['line']
  end

  def test_logs_without_messages_are_not_recorded
    in_transaction do
      @logger.info
    end
    _, events = @aggregator.harvest!

    assert_predicate(events, :empty?)
  end

  def test_logs_with_empty_messages_are_not_recorded
    in_transaction do
      @logger.info('')
    end
    _, events = @aggregator.harvest!

    assert_predicate(events, :empty?)
  end

  def test_logging_events_include_trace_linkng_metadata
    in_transaction do
      @logger.info('Test message')
    end
    _, events = @aggregator.harvest!

    assert events[0][1]['trace.id']
    assert events[0][1]['span.id']
  end

  def test_log_decorating_enabled_records_linking_metadata
    setup_string_appender

    with_config(:'application_logging.local_decorating.enabled' => true) do
      in_transaction do
        @logger.info('Decorate me!')
      end
    end

    log_output = @written.string

    assert_match(/Decorate me!/, log_output)
    assert_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end

  def test_log_decorating_disabled_does_not_record_linking_metadata
    setup_string_appender

    with_config(:'application_logging.local_decorating.enabled' => false) do
      in_transaction do
        @logger.info('Do not decorate me!')
      end
    end

    log_output = @written.string

    assert_match(/Do not decorate me!/, log_output)
    refute_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end

  def test_captures_mdc_data
    in_transaction do
      Logging.mdc['user_id'] = '12345'
      Logging.mdc['request_id'] = 'abc-def'
      @logger.info('Test with MDC')
    end
    _, events = @aggregator.harvest!

    assert_equal '12345', events[0][1]['mdc.user_id']
    assert_equal 'abc-def', events[0][1]['mdc.request_id']
  end

  def test_multiple_appenders_record_one_event
    setup_string_appender
    second_output = StringIO.new
    second_appender = Logging.appenders.io('second_appender', second_output)

    @logger.add_appenders(second_appender)

    in_transaction do
      @logger.info('Message to multiple appenders')
    end
    _, events = @aggregator.harvest!

    assert_equal 1, events.length
    assert_equal 'INFO', events[0][1]['level']
    assert_match(/Message to multiple appenders/, @written.string)
    assert_match(/Message to multiple appenders/, second_output.string)
  end

  def test_logger_with_json_appender_layout
    json_appender = Logging.appenders.rolling_file(
      'development.log', :age => 'daily', :layout => Logging.layouts.json
    )

    layout_logger = Logging.logger('json_layout_logger')
    layout_logger.add_appenders(json_appender)
    layout_logger.level = :info

    in_transaction do
      layout_logger.info('JSON layout test message')
    end
    _, events = @aggregator.harvest!

    assert_equal 1, events.length
    assert_equal 'INFO', events[0][1]['level']
    assert_equal 'json_layout_logger', events[0][1]['logger']
    assert_equal 'JSON layout test message', events[0][1]['message']

    FileUtils.rm_f('json_layout_logger')
    FileUtils.rm_f('development.log')
    FileUtils.rm_f('development.log.age')
  end

  def test_logger_level_filtering
    filtered_logger = Logging.logger('filtered_severity_logger')
    filtered_output = StringIO.new
    filtered_logger.level = :warn

    in_transaction do
      filtered_logger.info('Info message - should be filtered')
      filtered_logger.warn('Warn message - should be captured')
    end
    _, events = @aggregator.harvest!

    assert_equal 1, events.length
    assert_equal 'WARN', events[0][1]['level']
    assert_equal 'Warn message - should be captured', events[0][1]['message']

    Logging.logger['filtered_severity_logger']&.clear_appenders
    FileUtils.rm_f('filtered_severity_logger')
  end

  def test_forwarding_threshold_filtering
    with_config(:'application_logging.forwarding.log_level' => 'WARN') do
      in_transaction do
        @logger.debug('Debug message - should be filtered')
        @logger.info('Info message - should be filtered')
        @logger.warn('Warn message - should be forwarded')
        @logger.error('Error message - should be forwarded')
      end
      _, events = @aggregator.harvest!

      assert_equal 2, events.length
      assert_equal 'WARN', events[0][1]['level']
      assert_equal 'ERROR', events[1][1]['level']
    end
  end

  def test_forwarding_threshold_allows_custom_levels
    with_config(:'application_logging.forwarding.log_level' => 'ERROR') do
      in_transaction do
        @logger.info('Info message - should be filtered')
        @logger.custom_level_meow('Custom level message - should always be forwarded')
        @logger.error('Error message - should be forwarded')
      end
      _, events = @aggregator.harvest!

      assert_equal 2, events.length
      assert_equal 'CUSTOM_LEVEL_MEOW', events[0][1]['level']
      assert_equal 'ERROR', events[1][1]['level']
    end
  end
end
