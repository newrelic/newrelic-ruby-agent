# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Connection

      def record_spans streaming_buffer
        rpc.record_span streaming_buffer, metadata: metadata
      end

      def channel
        Channel.instance.channel
      end

      def build_stub
        Com::Newrelic::Trace::V1::IngestService::Stub.new(grpc_host, channel_creds, channel_override: channel, timeout: 10)
      end

      def rpc
        @rpc ||= build_stub
      end

      def start_agent
        return if local?

        return if NewRelic::Agent.agent.connected?
        NewRelic::Agent.manual_start

        # Wait for the agent to connect so we'll have an agent run token
        puts 'waiting...'
        sleep(0.05) while !NewRelic::Agent.agent.connected?
      end

      def agent_run_token
        return "local_token" if local?

        @agent_run_token ||= begin
          start_agent
          NewRelic::Agent.agent.service.agent_id
        end
      end

      def metadata
        @metadata ||= {
          "license_key" => "something",
          "agent_run_token" => agent_run_token
        }
      end

    end
  end
end
