# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

class DontForwardStandardStreamLoggerOutputTest < Minitest::Test
  include MultiverseHelpers

  def setup
    reset_everything
  end

  def teardown
    reset_everything
  end

  def test_stdout_logger_is_marked_for_skipping
    stdout_logger = ::Logger.new($stdout)
    string_logger = ::Logger.new(StringIO.new)
    message = 'I cut down trees, I eat my lunch'
    [stdout_logger, string_logger].map { |logger| logger.info(message) }
    assert_equal [true, false], [stdout_logger.skip_instrumenting?, string_logger.skip_instrumenting?]
  end

  def test_stderr_logger_is_marked_for_skipping
    stderr_logger = ::Logger.new($stderr)
    string_logger = ::Logger.new(StringIO.new)
    message = 'On Wednesdays I go shopping and have buttered scones for tea'
    [stderr_logger, string_logger].map { |logger| logger.info(message) }
    assert_equal [true, false], [stderr_logger.skip_instrumenting?, string_logger.skip_instrumenting?]
  end

  def test_stdout_logger_is_not_skipped_when_solo
    stdout_logger = ::Logger.new($stdout)
    stdout_logger.info('I sleep all night and I work all day')
    assert !stdout_logger.skip_instrumenting?
  end

  def test_stderr_logger_is_not_skipped_when_solo
    stderr_logger = ::Logger.new($stderr)
    stderr_logger.info('I like to press wild flowers')
    assert !stderr_logger.skip_instrumenting?
  end

  def test_duped_standard_stream_handle
    duped_stream_logger = ::Logger.new(STDOUT.dup)
    string_logger = ::Logger.new(StringIO.new)
    message = 'The towering Wattle of Aldershot'
    [duped_stream_logger, string_logger].map { |logger| logger.info(message) }
    assert_equal [true, false], [duped_stream_logger.skip_instrumenting?, string_logger.skip_instrumenting?]
  end

  def reset_everything
    NewRelic::Agent.instance.log_event_aggregator.reset!
    NewRelic::Agent.instance.log_event_aggregator.instance_variable_set(:@loggers, {})
  end
end
