# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Client
      include Com::Newrelic::Trace::V1
 
      # FOREVER = (2**(4 * 8 -2) -1)
      # THIRTY_SECONDS = 30_000
 
      def initialize port=10000
        @port = port
        @response = nil
        @record_status_stream = nil
        @metadata = nil
        @streaming_buffer = nil
        @mutex = Mutex.new
        @connected = NewRelic::Agent.agent.connected?
        @agent_started = ConditionVariable.new
        register_config_callback
      end

      def register_config_callback
        events = NewRelic::Agent.agent.events
        events.subscribe(:server_source_configuration_added) do
          @metadata = nil
          @mutex.synchronize do
            @connected = true
            @agent_started.signal
            restart_streaming
          end
        end
      end

      def close_stream
        if @record_status_stream
          @record_status_stream.exit
          @record_status_stream = nil
        end
      end

      def restart_streaming
        close_stream

        if @streaming_buffer
          @streaming_buffer.restart
        else
          @streaming_buffer = StreamingBuffer.new Config.span_events_queue_size
        end
  
        start_streaming @streaming_buffer
      end

      def start_streaming streaming_buffer
        stream_record_status rpc.record_span(streaming_buffer, metadata: metadata)
      end
      
      def rpc
        @rpc ||= Com::Newrelic::Trace::V1::IngestService::Stub.new(
          Channel.instance.host, 
          Channel.instance.credentials, 
          channel_override: Channel.instance
        )
      end

      def agent_id
        NewRelic::Agent.agent.service.agent_id
      end

      def license_key
        NewRelic::Agent.config[:license_key]
      end

      def metadata
        return @metadata if @metadata

        @mutex.synchronize do
          @agent_started.wait(@mutex) if !@connected

          @metadata = {
            "license_key" => license_key,
            "agent_run_token" => agent_id
          }
        end
      end

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