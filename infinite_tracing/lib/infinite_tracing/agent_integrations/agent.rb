# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  NewRelic::Agent.logger.debug "Installing Infinite Tracer in Agent"
  
  Agent.class_eval do

    def new_infinite_tracer
      # We must start streaming in a thread or we block/deadlock the
      # entire start up process for the Agent.
      InfiniteTracing::Client.new.tap do |client| 
        @infinite_tracer_thread = InfiniteTracing::Worker.new(:infinite_tracer) do 
          NewRelic::Agent.logger.debug "Opening Infinite Tracer Stream with gRPC server"
          client.start_streaming
        end
      end
    end

    def close_infinite_tracer
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
