# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

# The connection class manages the channel and connection to the gRPC server.
#
# Calls to the gRPC server are blocked until the agent connects to the collector
# and obtains a license_key and agent_run_token from the server side configuration.
#
# If the agent is instructed to reconnect by the collector, that event triggers
# server_source_configuration_added, which this connection is subscribed to and will
# also notify the client to restart and re-establish its bi-directional streaming
# with the gRPC server.
#
# NOTE: Connection is implemented as a Singleton and it also only ever expects *one*
# client instance by design.
module NewRelic::Agent
  module InfiniteTracing
    class Connection

      class << self
        def instance
          @@instance ||= new
        end

        def reset
          @@instance.reset if defined?(@@instance) && @@instance
          @@instance = new
        end
       
        def record_spans client, enumerator
          instance.client = client
          instance.rpc.record_span enumerator, metadata: metadata
        end

        def record_span_batches client, enumerator
          instance.client = client
          instance.rpc.record_span_batch enumerator, metadata: metadata
        end

        def metadata
          instance.metadata
        end
      end

      def client= new_client
        if !@client.nil? && @client != new_client
          NewRelic::Agent.logger.warn "Infinite Tracing's Connection is discarding its @client reference unexpectedly!"
        end
        @client = new_client
      end

      def initialize_stub
        @lock.synchronize { Channel.new.stub }
      end

      def rpc
       @rpc ||= Channel.new.stub
      end

      # The metadata for the RPC calls is a blocking call
      # waiting for the Agent to connect and receive the 
      # server side configuration, which contains the license_key
      # as well as the agent_id (agent_run_token).
      def metadata
        return @metadata if @metadata

        @lock.synchronize do
          @agent_started.wait(@lock) if !@agent_connected

          @metadata = {
            "license_key" => license_key,
            "agent_run_token" => agent_id
          }
        end
      end

      def reset
        return unless @callback_handler
        @callback_handler.unsubscribe
      end

      private 

      def initialize
        @client = nil
        @rpc = nil
        @metadata = nil

        @agent_connected = NewRelic::Agent.agent.connected?
        @agent_started = ConditionVariable.new
        @lock = Mutex.new
        register_config_callback
      end

      def register_config_callback
        events = NewRelic::Agent.agent.events
        @callback_handler = events.subscribe(:server_source_configuration_added) do
          @lock.synchronize do
            @rpc = nil
            @metadata = nil
            @agent_connected = true
            @agent_started.signal
          end
          @client.restart if @client
        end
      end

      def agent_id
        NewRelic::Agent.agent.service.agent_id.to_s
      end

      def license_key
        NewRelic::Agent.config[:license_key]
      end
    end
  end
end
