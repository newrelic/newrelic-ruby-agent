# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Base class for startup logging and testing in multiverse

module NewRelic
  module Agent
    class MemoryLogger
      def initialize
        @messages = []
      end

      def is_startup_logger?
        true
      end

      attr_accessor :messages, :level

      def fatal(*msgs)
        messages << [:fatal, msgs]
      end

      def error(*msgs)
        messages << [:error, msgs]
      end

      def warn(*msgs)
        messages << [:warn, msgs]
      end

      def info(*msgs)
        messages << [:info, msgs]
      end

      def debug(*msgs)
        messages << [:debug, msgs]
      end

      def log_exception(level, e, backtrace_level=level)
        messages << [:log_exception, [level, e, backtrace_level]]
      end

      def dump(logger)
        messages.each do |(method, args)|
          logger.send(method, *args)
        end
        messages.clear
      end
    end
  end
end
