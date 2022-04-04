# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/logging'

class LoggingTest < Performance::TestCase
  EXAMPLE_MESSAGE = 'This is an example message'.freeze

  def test_decorating_logger
    io = StringIO.new
    logger = NewRelic::Agent::Logging::DecoratingLogger.new io
    measure do
      logger.info EXAMPLE_MESSAGE
    end
  end

  def test_logger_instrumentation
    io = StringIO.new
    logger = ::Logger.new io
    measure do
      logger.info EXAMPLE_MESSAGE
    end
  end

  def test_local_log_decoration
    io = StringIO.new
    logger = ::Logger.new io
    measure do
      with_config(:'application_logging.local_decorating.enabled' => true) do
        logger.info EXAMPLE_MESSAGE
      end
    end
  end

  def test_local_log_decoration_in_transaction
    io = StringIO.new
    logger = ::Logger.new io
    measure do
      with_config(:'application_logging.local_decorating.enabled' => true) do
        in_transaction do
          logger.info EXAMPLE_MESSAGE
        end
      end
    end
  end

  def test_logger_instrumentation_in_transaction
    io = StringIO.new
    logger = ::Logger.new io
    measure do
      in_transaction do
        logger.info EXAMPLE_MESSAGE
      end
    end
  end
end
