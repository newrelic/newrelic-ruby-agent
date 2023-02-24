# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  NewRelic::Agent.logger.debug("Installing Infinite Tracer in Agent")

  Agent.class_eval do
    def new_infinite_tracer
      # We must start streaming in a thread or we block/deadlock the
      # entire start up process for the Agent.
      InfiniteTracing::Client.new.tap do |client|
        @infinite_tracer_thread = InfiniteTracing::Worker.new(:infinite_tracer) do
          NewRelic::Agent.logger.debug("Opening Infinite Tracer Stream with gRPC server")
          client.start_streaming
        end
      end
    end

    # Handles the case where the server tells us to restart -
    # this clears the data, clears connection attempts, and
    # waits a while to reconnect.
    def handle_force_restart(error)
      ::NewRelic::Agent.logger.debug(error.message)
      drop_buffered_data
      @service&.force_restart
      @connect_state = :pending
      close_infinite_tracer
      sleep(30)
    end

    # Whenever we reconnect, close and restart
    def close_infinite_tracer
      NewRelic::Agent.logger.debug("Closing infinite tracer threads")
      return unless @infinite_tracer_thread

      @infinite_tracer_thread.join
      @infinite_tracer_thread.stop
      @infinite_tracer_thread = nil
    end

    def infinite_tracer
      @infinite_tracer ||= new_infinite_tracer
    end
  end
end
