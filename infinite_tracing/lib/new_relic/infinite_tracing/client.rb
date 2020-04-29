# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Client

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
        buffer.flush
      end

      def initialize
        start_streaming
      end

      def restart
        old_buffer = @buffer
        @buffer = StreamingBuffer.new
        old_buffer.transfer_to @buffer
        start_streaming
      end

      def start_streaming
        @response_handler = record_spans
      end

      def record_spans
        RecordStatusHandler.new Connection.record_spans(buffer.enumerator)
      end

      def record_span_batches
        RecordStatusHandler.new Connection.record_span_batches(buffer.batch_enumerator)
      end

      private

      # def start_streaming
      #   require 'pry'; binding.pry #RLK
      #   RecordStatusHandler.new rpc.record_span(buffer, metadata: metadata)
      # rescue => err
      #   NewRelic::Agent.logger.error "gRPC failed to start streaming to record_span", err
      #   puts err
      #   puts err.backtrace
      # end

      # def start_streaming_batches
      #   require 'pry'; binding.pry #RLK
      #   ResponseHandler.new rpc.record_span_batch(buffer, metadata: metadata)
      # rescue => err
      #   NewRelic::Agent.logger.error "gRPC failed to start streaming to record_span_batch", err
      #   puts err
      #   puts err.backtrace
      # end

    end

  end
end
