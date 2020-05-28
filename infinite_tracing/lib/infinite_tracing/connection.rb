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
        def record_spans client, enumerator, exponential_backoff
          instance.record_spans client, enumerator, exponential_backoff
        end

        # RPC calls will pass the calling client instance in.  We track this
        # so we're able to signal the client to restart when connectivity to the
        # server is disrupted.
        def record_span_batches client, enumerator, exponential_backoff
          instance.record_span_batch client, enumerator, exponential_backoff
        end

        def metadata
          instance.metadata
        end
      end

      # We attempt to connect and record spans with reconnection backoff in order to deal with
      # unavailable errors coming from the stub being created and record_span call
      def record_spans client, enumerator, exponential_backoff
          @active_clients[client] = client
          with_reconnection_backoff(exponential_backoff) { rpc.record_span enumerator, metadata: metadata }
      end

      # RPC calls will pass the calling client instance in.  We track this
      # so we're able to signal the client to restart when connectivity to the
      # server is disrupted.
      def record_span_batches client, enumerator, exponential_backoff
        @active_clients[client] = client
        with_reconnection_backoff(exponential_backoff) { rpc.record_span_batch enumerator, metadata: metadata }
      end

      # Acquires the new channel stub for the RPC calls.
      # We attempt to connect and record spans with reconnection backoff in order to deal with
      # unavailable errors coming from the stub being created and record_span call
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

      # Initializes rpc so we can get a Channel and Stub (connect to gRPC server)
      # Initializes metadata so we use newest values in establishing channel
      # Sets the agent_connected flag and signals the agent started so any
      # waiting locks (rpc calls ahead of the agent connecting) can proceed.
      def notify_agent_started
        @lock.synchronize do
          @rpc = nil
          @metadata = nil
          @agent_connected = true
          @agent_started.signal
        end
        @active_clients.each_value(&:restart)
      end

      private

      # prepares the connection to wait for the agent to connect and have an
      # agent_run_token ready for metadata on rpc calls.
      def initialize
        @active_clients = {}
        @rpc = nil
        @metadata = nil
        @connection_attempts = 0
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

      # Continues retrying the connection at backoff intervals until a successful connection is made
      def with_reconnection_backoff exponential_backoff=true, &block
        @connection_attempts = 0
        begin
          yield
        rescue => exception
          retry_connection_period = retry_connection_period(exponential_backoff)
          ::NewRelic::Agent.logger.error "Error establishing connection with infinite tracing service:", exception
          ::NewRelic::Agent.logger.info "Will re-attempt infinte tracing connection in #{retry_connection_period} seconds"
          sleep retry_connection_period
          note_connect_failure
          retry
        end
      end

      def retry_connection_period exponential_backoff=true
        if exponential_backoff
          NewRelic::CONNECT_RETRY_PERIODS[@connection_attempts] || NewRelic::MAX_RETRY_PERIOD
        else
          NewRelic::MIN_RETRY_PERIOD
        end
      end

      # broken out to help for testing
      def note_connect_failure
        @connection_attempts += 1
      end

    end
  end
end
