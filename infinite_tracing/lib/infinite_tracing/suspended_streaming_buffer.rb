# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# The SuspendedStreamingBuffer class discards pushed segments and records 
# the seen metric.  This buffer is installed when the gRPC server returns 
# UNIMPLEMENTED (status 12) code as a signal to not reconnect to the server.
module NewRelic::Agent
  module InfiniteTracing
    class SuspendedStreamingBuffer
      include Constants
      extend Forwardable
      def_delegators :@empty_buffer, :empty?, :push

      def initialize max_size = DEFAULT_QUEUE_SIZE
        @empty_buffer = NewRelic::EMPTY_ARRAY
      end

      # updates the seen metric and discards the segment
      def << segment
        NewRelic::Agent.increment_metric SPANS_SEEN_METRIC
      end

      def transfer new_buffer
        # NOOP
      end

      def close_queue
        # NOOP
      end
      alias :flush_queue :close_queue
      
      def enumerator
        @empty_buffer
      end
    end
  end
end
