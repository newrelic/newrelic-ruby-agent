# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Client
      include Com::Newrelic::Trace::V1
 
      FOREVER = (2**(4 * 8 -2) -1)
      THIRTY_SECONDS = 30_000
 
      def initialize port=10000
        @port = port
        @response = nil
        @watch = nil
        start_agent
      end

      def local?
        Config.local?
      end

      def channel_creds
        local? ? :this_channel_is_insecure : GRPC::Core::ChannelCredentials.new
      end

      def grpc_host
        Config.trace_observer_uri
      end

      def channel
        return @channel if @channel

        channel_args = {
          'grpc.minimal_stack' => 1,
          # 'grpc.arg_max_connection_idle_ms' => FOREVER,
          # 'grpc.keepalive_time_ms' => THIRTY_SECONDS,
          # 'grpc.keepalive_timeout_ms' => THIRTY_SECONDS,
          # 'grpc.keepalive_permit_without_calls' => THIRTY_SECONDS,
          # 'grpc.arg_max_concurrent_streams' => 10,
          # 'grpc.max_concurrent_streams' => 10,
          # 'grpc.max_connection_age_ms' => FOREVER,
          # 'grpc.enable_deadline_checking' => 0,
          # 'grpc.http2.max_pings_without_data' => 0,
          # 'grpc.http2.min_time_between_pings_ms' => 10000,
          # 'grpc.http2.min_ping_interval_without_data_ms' => 5000,
         }
        @channel = GRPC::ClientStub.setup_channel(nil, grpc_host, channel_creds, channel_args)
      end

      def build_stub_for_client
        Com::Newrelic::Trace::V1::IngestService::Stub.new(grpc_host, channel_creds, channel_override: channel, timeout: 10)
      end

      def client
        @client ||= build_stub_for_client
      end

      def start_agent
        return if NewRelic::Agent.agent.connected?
        NewRelic::Agent.manual_start

        # Wait for the agent to connect so we'll have an agent run token
        sleep(0.05) while !NewRelic::Agent.agent.connected?
      end

      def agent_run_token
        @agent_run_token ||= begin
          start_agent
          NewRelic::Agent.agent.service.agent_id
        end
      end

      def license_key
        "BOGUS"
      end

      def metadata
        @metadata ||= {
          "license_key" => license_key,
          "agent_run_token" => agent_run_token
        }
      end

      def finish
        @watch.exit if @watch
      end

      def stream_record_status record_status_stream
        @watch = Thread.new do
          begin
            record_status_stream.each do |r|
              puts "RECORD STATUS: #{r.inspect}"
            end
          rescue => e
            puts "THREAD EX! #{e.inspect}"
          end
        end
      rescue => e
        puts e.inspect
      end

      def record_spans streaming_buffer
        streaming_buffer.start
        response = client.record_span(publisher, metadata: metadata)
      end
    end

  end
end