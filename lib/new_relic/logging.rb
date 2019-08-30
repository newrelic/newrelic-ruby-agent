# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'json'
require 'new_relic/agent'
require 'new_relic/agent/null_logger'

module NewRelic
  module Logging
    extend self

    class DecoratingJsonFormatter < ::Logger::Formatter
      TIMESTAMP_KEY = 'timestamp'.freeze
      MESSAGE_KEY = 'message'.freeze
      LOG_LEVEL_KEY = 'log.level'.freeze
      LOG_NAME_KEY = 'logger.name'.freeze
      NEWLINE = "\n".freeze

      def call severity, time, progname, msg
        metadata = NewRelic::Agent.linking_metadata
        metadata[TIMESTAMP_KEY] = (time.to_f * 1000).round
        metadata[MESSAGE_KEY] = (String === msg ? msg : msg.inspect)
        metadata[LOG_LEVEL_KEY] = severity
        metadata[LOG_NAME_KEY] = progname if progname

        JSON.dump(metadata) << NEWLINE
      end
    end

    # This class decorates logs with trace and entity metadata, and emits log
    # messages formatted as JSON objects.  It extends the Logger class from
    # the Ruby standard library, and accepts the same constructor parameters.
    #
    # It can be added to a Rails application like this:
    #
    #   require 'newrelic_rpm'
    #
    #   Rails.application.configure do
    #     config.logger = NewRelic::Logging::DecoratingLogger.new "log/#{Rails.env}.log"
    #   end
    #
    # @api public
    class DecoratingLogger < (defined?(::ActiveSupport) && defined?(::ActiveSupport::Logger) ? ::ActiveSupport::Logger : ::Logger)

      alias :write :info

      def initialize *args
        super
        self.formatter = DecoratingJsonFormatter.new
      end
    end
  end
end
