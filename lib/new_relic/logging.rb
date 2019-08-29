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

    class DecoratingLogger < (defined?(::ActiveSupport) ? ::ActiveSupport::Logger : ::Logger)

      alias :write :info

      def initialize *args
        super
        self.formatter = DecoratingJsonFormatter.new
      end
    end
  end
end
