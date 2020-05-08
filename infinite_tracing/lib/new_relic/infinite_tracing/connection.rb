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

      # listens for server side configurations added to the agent.  When a new config is
      # added, we have a new agent run token and need to restart the client's RPC stream
      # with the new metadata information.
      NewRelic::Agent.agent.events.subscribe(:server_source_configuration_added) do
        begin
          Connection.instance.notify_agent_started
        rescue => error
          NewRelic::Agent.logger.error \
            "Error during notify :server_source_configuration_added event", 
            error
        end
      end

      class << self

        def instance
          @@instance ||= new
        end

        def reset
          @@instance = new
        end
       
        # RPC calls will pass the calling client instance in.  We track this
        # so we're able to signal the client to restart when connectivity to the 
        # server is disrupted.
        def record_spans client, enumerator
          instance.client = client
          instance.rpc.record_span enumerator, metadata: metadata
        end

        # RPC calls will pass the calling client instance in.  We track this
        # so we're able to signal the client to restart when connectivity to the 
        # server is disrupted.
        def record_span_batches client, enumerator
          instance.client = client
          instance.rpc.record_span_batch enumerator, metadata: metadata
        end

        def metadata
          instance.metadata
        end
      end

      # the client instance is passed through on the RPC calls.  Although client is not a Singleton
      # pattern per se, we are _not_ expecting it to be different between rpc calls.  The guard clause
      # here ensures we're coding per this expectation.
      def client= new_client
        if !@client.nil? && @client != new_client
          NewRelic::Agent.logger.warn "Infinite Tracing's Connection is discarding its @client reference unexpectedly!"
        end
        @client = new_client
      end

      # acquires the new channel stub for the RPC calls.
      def rpc
       @rpc ||= Channel.new.stub
      end

      # The metadata for the RPC calls is a blocking call waiting for the Agent to 
      # connect and receive the server side configuration, which contains the license_key
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

      def notify_agent_started
        @lock.synchronize do
          @rpc = nil
          @metadata = nil
          @agent_connected = true
          @agent_started.signal
        end
        @client.restart if @client
      end

      private 

      # prepares the connection to wait for the agent to connect and have an
      # agent_run_token ready for metadata on rpc calls.
      def initialize
        @client = nil
        @rpc = nil
        @metadata = nil

        @agent_connected = NewRelic::Agent.agent.connected?
        @agent_started = ConditionVariable.new
        @lock = Mutex.new
      end

      # The agent run token, which is only available after a server source configuration has
      # been added to the agent's config stack.
      def agent_id
        NewRelic::Agent.agent.service.agent_id.to_s
      end

      def license_key
        NewRelic::Agent.config[:license_key]
      end
    end
  end
end
