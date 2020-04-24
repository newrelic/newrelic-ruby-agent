# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Client
      # def initialize port=10000
      #   @connection = Connection.new port
      #   @response_handler = record_spans
      # end

      # def transfer previous_client
      #   previous_client.buffer.transfer buffer
      #   return self
      # end

      # def buffer
      #   @buffer ||= StreamingBuffer.new
      # end

      # def record_spans
      #   ResponseHandler.new @connection.record_spans(buffer.enumerator)
      # end

      # def flush
      #   buffer.flush
      # end
 
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

      def << segment
        puts "<<"
        @mutex.synchronize do
          puts "..<<.."
          @agent_started.wait(@mutex) if !@connected
          puts "..<<!.."
          @streaming_buffer << segment
        end
      end

      def close_stream
        if @record_status_stream
          puts "CLOSE_STREAM EXIT!"
          @record_status_stream.exit
          @record_status_stream = nil
        end
      end

      def restart_streaming
        puts 'RS'
        close_stream

        if @streaming_buffer
          @streaming_buffer.restart
        else
          @streaming_buffer = StreamingBuffer.new Config.span_events_queue_size
        end
  
        start_streaming
      end

      private

      def register_config_callback
        events = NewRelic::Agent.agent.events
        puts "RCC"
        events.subscribe(:server_source_configuration_added) do
          @metadata = nil
          @mutex.synchronize do
          puts "..RCC.."
            @connected = true
            @agent_started.signal
            restart_streaming
          end
        end
      end

      def start_streaming
        raise "no streaming buffer" if @streaming_buffer.nil?
        puts "SS #{Channel.instance.host}"
        rpc.record_span(@streaming_buffer, metadata: metadata)
      rescue => e
        puts e.inspect
      end
      
      def rpc
        @rpc ||= Com::Newrelic::Trace::V1::IngestService::Stub.new(
          Channel.instance.host, 
          Channel.instance.credentials, 
          channel_override: Channel.instance.channel
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

        puts "MD"
        @mutex.synchronize do
          puts "..MD.."
          @agent_started.wait(@mutex) if !@connected
          puts "..MD!.."

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