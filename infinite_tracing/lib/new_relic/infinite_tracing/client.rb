# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Client

      def << segment
        buffer << segment
      end

      # Transfers spans in streaming buffer from previous 
      # client (if any) and returns self (so we chain the call)
      def transfer previous_client
        return self unless previous_client
        previous_client.buffer.transfer buffer
        self
      end

      def buffer
        @buffer ||= StreamingBuffer.new
      end

      def flush
        buffer.flush_queue
      end

      def initialize
        start_streaming
      end

      def restart
        old_buffer = @buffer
        @buffer = StreamingBuffer.new
        old_buffer.transfer @buffer
        start_streaming
      end

      def start_streaming
        @response_handler = record_spans
      end

      def record_spans
        RecordStatusHandler.new Connection.record_spans(self, buffer.enumerator)
      end

      def record_span_batches
        RecordStatusHandler.new Connection.record_span_batches(self, buffer.batch_enumerator)
      end

    end

  end
end
