# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class RecordStatusHandler
      def initialize client, enumerator
        @client = client
        @enumerator = enumerator
        @messages_seen = nil
        @lock = Mutex.new
        @lock.synchronize { @worker = start_handler }
      end

      def messages_seen
        @messages_seen ? @messages_seen.messages_seen : 0
      end

      def start_handler
        Worker.new self.class.name do
          begin
            @enumerator.each do |response|
              break if response.nil? || response.is_a?(Exception)
              @lock.synchronize do
                @messages_seen = response
                NewRelic::Agent.logger.debug "gRPC Infinite Tracer Observer saw #{messages_seen} messages"
              end
            end
            NewRelic::Agent.logger.debug "gRPC Infinite Tracer Observer closed the stream"
            @client.handle_close
          rescue => error
            @client.handle_error error
          end
        end
      rescue => error
        NewRelic::Agent.logger.error "gRPC Worker Error", error
      end

      def stop
        return if @worker.nil?
        @lock.synchronize do
          NewRelic::Agent.logger.debug "gRPC Stopping Response Handler"
          @worker.stop
          @worker = nil
        end
      end
    end
  end
end