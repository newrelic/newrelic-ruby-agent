# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class RecordStatusHandler
      def initialize enumerator
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
              @lock.synchronize { @messages_seen = response }
            end
          rescue GRPC::DeadlineExceeded => err
            NewRelic::Agent.record_metric("Supportability/InfiniteTracing/Span/Response/Error", 0.0)
            NewRelic::Agent.logger.error "gRPC Deadline Exceeded", err
          rescue => err
            NewRelic::Agent.record_metric("Supportability/InfiniteTracing/Span/Response/Error", 0.0)
            NewRelic::Agent.logger.error "gRPC Unexpected Error", err
          end
        end
      rescue => err
        NewRelic::Agent.logger.error "gRPC Worker Error", err
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