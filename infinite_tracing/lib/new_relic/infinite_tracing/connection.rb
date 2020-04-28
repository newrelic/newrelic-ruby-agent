# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Connection
      include Singleton

      # def self.instance
      #   @instance ||= new
      # end

      def record_spans enumerator
        rpc.record_span enumerator, metadata: metadata
      end

      def record_span_batches enumerator
        rpc.record_span_batch enumerator, metadata: metadata
      end

      private

      def initialize
        @rpc = nil
        @metadata = nil

        @connected = NewRelic::Agent.agent.connected?
        @agent_started = ConditionVariable.new
        @lock = Mutex.new

        register_config_callback
      end

      def register_config_callback
        events = NewRelic::Agent.agent.events
        events.subscribe(:server_source_configuration_added) do
          @rpc = nil
          @metadata = nil
          @lock.synchronize do
            @connected = true
            @agent_started.signal
          end
        end
      end

      private

      def rpc
        @rpc ||= Com::Newrelic::Trace::V1::IngestService::Stub.new(
          Channel.instance.host,
          Channel.instance.credentials,
          channel_override: Channel.instance.channel
        )
      end

      def agent_id
        NewRelic::Agent.agent.service.agent_id.to_s
      end

      def license_key
        NewRelic::Agent.config[:license_key]
      end

      # The metadata for the RPC calls is a blocking call
      # waiting for the Agent to connect and receive the 
      # server side configuration, which contains the license_key
      # as well as the agent_id (agent_run_token).
      def metadata
        return @metadata if @metadata

        @lock.synchronize do
          @agent_started.wait(@lock) if !@connected

          @metadata = {
            "license_key" => license_key,
            "agent_run_token" => agent_id
          }
        end
      end

      def register_config_callback
        events = NewRelic::Agent.agent.events
        events.subscribe(:server_source_configuration_added) do
          @metadata = nil
          @lock.synchronize do
            @connected = true
            @agent_started.signal
          end
        end
      end

    end
  end
end
