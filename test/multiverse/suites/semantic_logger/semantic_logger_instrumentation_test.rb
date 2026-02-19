# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class SemanticLoggerInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  def setup
    @logger = SemanticLogger['test_logger']
    @logger.level = :trace

    @aggregator = NewRelic::Agent.agent.log_event_aggregator
    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def setup_local_appender
    @written = StringIO.new
    @appender = SemanticLogger.add_appender(io: @written, formatter: :default)
  end

  def flush_semantic_logger
    # Our instrumentation hooks in as an appender, so finish
    # appender log threads.
    ::SemanticLogger.flush
  end

  def test_no_instrumentation_when_disabled
    with_config(:'instrumentation.semantic_logger' => 'disabled') do
      @logger.info('Test message')                                                                        
      flush_semantic_logger                                                                 
    end
    _, events = @aggregator.harvest!
                                      
    assert_empty(events)                                                               
  end 

  def test_level_is_recorded
    in_transaction do
      @logger.info('Test message')
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_metrics_recorded(%w[Logging/lines/INFO])
  end

  def test_log_levels_are_recorded
    in_transaction do
      @logger.trace('Trace message')
      @logger.debug('Debug message')
      @logger.info('Info message')
      @logger.warn('Warning message')
      @logger.error('Error message')
      @logger.fatal('Fatal message')
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert_equal 'TRACE', events[0][1]['level']
    assert_equal 'DEBUG', events[1][1]['level']
    assert_equal 'INFO', events[2][1]['level']
    assert_equal 'WARN', events[3][1]['level']
    assert_equal 'ERROR', events[4][1]['level']
    assert_equal 'FATAL', events[5][1]['level']
    assert_metrics_recorded(%w[Logging/lines/TRACE])
    assert_metrics_recorded(%w[Logging/lines/DEBUG])
    assert_metrics_recorded(%w[Logging/lines/INFO])
    assert_metrics_recorded(%w[Logging/lines/WARN])
    assert_metrics_recorded(%w[Logging/lines/ERROR])
    assert_metrics_recorded(%w[Logging/lines/FATAL])
  end

  def test_semantic_logger_attributes_are_recorded
    in_transaction do
      @logger.info('Test message', user_id: 123, action: 'login')
    end
    flush_semantic_logger  
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_equal 'test_logger', events[0][1]['name']
    assert_equal 123, events[0][1]['user_id']
    assert_equal 'login', events[0][1]['action']
  end

  def test_logs_without_messages_are_not_recorded
    in_transaction do
      @logger.info('')
    end
    _, events = @aggregator.harvest!

    assert_predicate(events, :empty?)
  end

  def test_semantic_logger_events_include_trace_linking_metadata
    in_transaction do
      @logger.info('Test message')
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert events[0][1]['timestamp']
    assert_equal 'INFO', events[0][1]['level']
    assert_equal 'Test message', events[0][1]['message']
  end

  def test_log_decorating_enabled_records_linking_metadata
    setup_local_appender

    with_config(:'application_logging.local_decorating.enabled' => true) do
      in_transaction do
        @logger.info('Decorate me!')
        flush_semantic_logger  
      end
    end
    log_output = @written.string

    assert_match(/Decorate me!/, log_output)
    assert_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end

  def test_log_decorating_disabled_does_not_record_linking_metadata
    setup_local_appender

    with_config(:'application_logging.local_decorating.enabled' => false) do
      in_transaction do
        @logger.info('Do not decorate me!')
      end
    end
    flush_semantic_logger
    log_output = @written.string

    assert_match(/Do not decorate me!/, log_output)
    refute_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end

  def test_forwarding_threshold_filtering
    with_config(:'application_logging.forwarding.log_level' => 'WARN') do
      in_transaction do
        @logger.debug('Debug message - should be filtered')
        @logger.info('Info message - should be filtered')
        @logger.warn('Warn message - should be forwarded')
        @logger.error('Error message - should be forwarded')
      end
      flush_semantic_logger
      _, events = @aggregator.harvest!

      assert_equal 2, events.length
      assert_equal 'WARN', events[0][1]['level']
      assert_equal 'ERROR', events[1][1]['level']
    end
  end

  def test_multiple_appenders_record_one_event
    setup_local_appender

    second_output = StringIO.new
    SemanticLogger.add_appender(io: second_output, formatter: :json)

    in_transaction do
      @logger.info('Message to multiple appenders')
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert_equal 1, events.length
    assert_equal 'INFO', events[0][1]['level']
    assert_match(/Message to multiple appenders/, @written.string)
    assert_match(/Message to multiple appenders/, second_output.string)
  end

  def test_high_security_mode_blocks_forwarding
    with_config(:high_security => true) do
      in_transaction do
        @logger.info('Should not be forwarded in high security mode')
      end
      flush_semantic_logger
      _, events = @aggregator.harvest!

      assert_empty(events)
    end
  end

  def test_application_logging_disabled_blocks_instrumentation
    with_config(:'application_logging.enabled' => false) do
      in_transaction do
        @logger.info('Should not be captured when application logging disabled')
      end
      flush_semantic_logger
      _, events = @aggregator.harvest!

      assert_empty(events)
    end
  end

  def test_captures_tags
    in_transaction do
      @logger.tagged('web', 'api') do
        @logger.info('Tagged message')
      end
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_equal 'Tagged message', events[0][1]['message']
    assert_equal ['web', 'api'], events[0][1]['tags']
  end

  def test_custom_logger_names
    custom_logger = SemanticLogger['CustomLogger']

    in_transaction do
      custom_logger.info('Custom logger message')
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert_equal 1, events.length
    assert_equal 'CustomLogger', events[0][1]['name']
    assert_equal 'Custom logger message', events[0][1]['message']
  end

  def test_handles_log_level_filtering_by_logger
    @logger.level = :warn

    in_transaction do
      @logger.info('Info message - should be filtered by logger')
      @logger.warn('Warn message - should be captured')
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert_equal 1, events.length
    assert_equal 'WARN', events[0][1]['level']
    assert_equal 'Warn message - should be captured', events[0][1]['message']
  end

  def test_captures_backtrace_when_available
    in_transaction do
      @logger.info('Message with backtrace', backtrace: caller)
    end
    flush_semantic_logger
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert events[0][1]['backtrace']
  end
end
