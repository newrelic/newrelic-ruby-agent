# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Client

      # def transfer previous_client
      #   previous_client.buffer.transfer buffer
      #   return self
      # end

      def buffer
        @buffer ||= StreamingBuffer.new
      end

      def flush
        buffer.flush
      end

      def initialize port=10000
        @port = port
        start_streaming
      end

      def << segment
        buffer << segment
      end

      def close_stream
        if @record_status_stream
          puts "CLOSE_STREAM EXIT!"
          @record_status_stream.exit
          @record_status_stream = nil
        end
      end

      def start_streaming
        record_spans
      end

      def connection
        @connection ||= Connection.new
      end

      def record_spans
        RecordStatusHandler.new connection.record_spans(buffer.enumerator)
      end

      def record_span_batches
        RecordStatusHandler.new connection.record_span_batches(buffer.batch_enumerator)
      end

      # def restart_streaming
      #   puts 'RS'
      #   close_stream

      #   if @streaming_buffer
      #     @streaming_buffer.restart
      #   else
      #     @streaming_buffer = StreamingBuffer.new Config.span_events_queue_size
      #   end

      #   start_streaming
      # end

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

      # def rpc
      #   @rpc ||= Com::Newrelic::Trace::V1::IngestService::Stub.new(
      #     Channel.instance.host,
      #     Channel.instance.credentials,
      #     channel_override: Channel.instance.channel
      #   )
      # end

      def stream_record_status record_status_stream
        @record_status_stream = Thread.new do
          begin
            record_status_stream.each do |r|
              NewRelic::Agent.logger.info "RECORD STATUS: #{r.inspect}"
            end
          rescue => e
            # TODO: RECONNECT!
            puts "THREAD EX! #{e.inspect}"
          end
        end
      rescue => e
        puts e.inspect
      end
    end

  end
end
