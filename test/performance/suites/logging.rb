# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class Logging < Performance::TestCase

  EXAMPLE_MESSAGE = 'This is an example message'.freeze

  def test_logging
    io = StringIO.new
    logger = ::NewRelic::Logging::DecoratingLogger.new io
    measure do
      logger.info EXAMPLE_MESSAGE
    end
  end
end
