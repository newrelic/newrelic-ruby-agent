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

      def fatal(*msgs, &blk)
        messages << [:fatal, blk, msgs]
      end

      def error(*msgs, &blk)
        messages << [:error, blk, msgs]
      end

      def warn(*msgs, &blk)
        messages << [:warn, blk, msgs]
      end

      def info(*msgs, &blk)
        messages << [:info, blk, msgs]
      end

      def debug(*msgs, &blk)
        messages << [:debug, blk, msgs]
      end

      def log_exception(level, e, backtrace_level=level)
        messages << [:log_exception, nil, [level, e, backtrace_level]]
      end

      def dump(logger)
        messages.each do |(method, blk, args)|
          logger.send(method, *args, &blk)
        end
        messages.clear
      end
    end
  end
end
