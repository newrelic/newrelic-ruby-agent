# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_buffer'

module NewRelic
  module Agent
    class ErrorEventAggregator
      def initialize
        #capacity will come from config
        @lock = Mutex.new
        @error_event_buffer = SampledBuffer.new(100)
      end

      def append_event noticed_error, transaction
        @lock.synchronize do
          @error_event_buffer.append_event do
            generate_event(noticed_error, transaction)
          end
        end
      end

      def generate_event noticed_error, transaction
        [noticed_error, transaction]
      end

      def harvest!
        @lock.synchronize do
          samples = @error_event_buffer.to_a
          @error_event_buffer.reset!
          samples
        end
      end

      def reset!
        @lock.synchronize do
          @error_event_buffer.reset!
        end
      end

      # old_samples will have already been transformed into
      # collector primitives by generate_event
      def merge! old_samples
        @lock.synchronize do
          old_samples.each { |s| @error_event_buffer.append_event(s) }
        end
      end
    end
  end
end
