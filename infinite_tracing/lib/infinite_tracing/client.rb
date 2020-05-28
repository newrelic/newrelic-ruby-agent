# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

# The Client class manages the streaming buffer with respect to the gRPC Connection.
#
# Restarting the client will cause a new connection to the gRPC server.
# When the client is restarted, a new streaming buffer is started and contents of old
# buffer are transferred to the new buffer.  
#
# Suspending the client will prevent the client from attempting to reconnect to the 
# gRPC server, but will still continue to record the span events `seen` metric.
module NewRelic::Agent
  module InfiniteTracing
    class Client
      include Constants

      def initialize
        @suspended = false
        @response_handler = nil
        @lock = Mutex.new
      end

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

      # provides the correct streaming buffer instance based on whether the
      # client is currently suspended.
      def new_streaming_buffer
        buffer_class = suspended? ? SuspendedStreamingBuffer : StreamingBuffer
        buffer_class.new Config.span_events_queue_size
      end

      def buffer
        @buffer ||= new_streaming_buffer
      end

      def flush
        buffer.flush_queue
      end

      # Turns camelcase base class name into upper snake case version of the name.
      def formatted_class_name class_name
        class_name = class_name.split(":")[-1]
        formatted_class_name = (class_name.gsub!(/(.)([A-Z])/,'\1_\2') || class_name).upcase
      end

      # Literal codes are all mapped to unique class names, so we can deduce the
      # name of the error to report in the metric from the error's class name.
      def grpc_error_metric_name error
        GRPC_ERROR_NAME_METRIC % formatted_class_name(error.class.name)
      end

      # Reports AND logs general response metric along with a more specific error metric
      def record_error_metrics_and_log error
        NewRelic::Agent.record_metric RESPONSE_ERROR_METRIC, 0.0
        if error.is_a? GRPC::BadStatus
          NewRelic::Agent.record_metric grpc_error_metric_name(error), 0.0
        else
          NewRelic::Agent.record_metric GRPC_OTHER_ERROR_METRIC, 0.0
        end
        NewRelic::Agent.logger.warn "gRPC response error received.", error
      end

      def handle_error error
        record_error_metrics_and_log error

        case error
        when GRPC::Unavailable then restart
        when GRPC::Unimplemented then suspend
        else
          # Set exponential backoff to false so we'll reconnect at periodic (15 second) intervals instead
          start_streaming false
        end
      end

      def suspended?
        @suspended
      end

      # Places the client into suspended state whereby client will no longer attempt to 
      # reconnect to the gRPC server nor will it attempt to send span events henceforth.
      # The Suspended Streaming Buffer will be installed in this state.
      def suspend
        return if suspended?
        @lock.synchronize do
          @suspended = true
          @buffer = new_streaming_buffer
          NewRelic::Agent.logger.warn "The Trace Observer host signaled to suspend streaming span events. " \
            "No more span events will be sent during this session."
        end
      end

      def restart
        @lock.synchronize do
          Connection.reset
          old_buffer = @buffer
          @buffer = new_streaming_buffer
          old_buffer.transfer @buffer
        end
        start_streaming
      end

      def stop
        return unless @response_handler
        @lock.synchronize do
          @response_handler.stop
          @response_handler = nil
        end
      end

      def start_streaming exponential_backoff=true
        return if suspended?
        @lock.synchronize { @response_handler = record_spans exponential_backoff }
      end

      def record_spans exponential_backoff
        RecordStatusHandler.new self, Connection.record_spans(self, buffer.enumerator, exponential_backoff)
      end

      def record_span_batches exponential_backoff
        RecordStatusHandler.new self, Connection.record_span_batches(self, buffer.batch_enumerator, exponential_backoff)
      end

    end

  end
end
