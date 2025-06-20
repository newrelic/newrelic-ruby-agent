# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'app'

# Rails's broadcast system sends identical log events to multiple loggers.
# This test makes sure that our code doesn't send two log events to New Relic.
class RailsLoggerTest < Minitest::Test
  include MultiverseHelpers
  setup_and_teardown_agent
  DEFAULT_LOG_PATH = 'log/development.log'

  def setup
    # Make sure the default logger destination is empty before we test
    File.truncate(DEFAULT_LOG_PATH, 0)

    @output = StringIO.new
    broadcasted_logger = Logger.new(@output)

    if NewRelic::Helper.version_satisfied?(Rails::VERSION::STRING, '>=', '7.1.0')
      Rails.logger.broadcast_to(broadcasted_logger)
    else
      Rails.logger.extend(ActiveSupport::Logger.broadcast(broadcasted_logger))
    end

    @aggregator = NewRelic::Agent.agent.log_event_aggregator
    @aggregator.reset!
  end

  def test_duplicate_logs_not_forwarded_by_rails_logger
    message = 'Can you hear me, Major Tom?'
    Rails.logger.debug(message)
    default_log_output = File.read(DEFAULT_LOG_PATH)

    assert_includes(@output.string, message, 'Broadcasted logger did not receive the message.')
    assert_includes(default_log_output, message, 'Default logger did not receive the message.')

    # LogEventAggregator sees the log only once
    assert_equal(1, @aggregator.instance_variable_get(:@seen))
    assert_equal({'DEBUG' => 1}, @aggregator.instance_variable_get(:@seen_by_severity))
  end
end
