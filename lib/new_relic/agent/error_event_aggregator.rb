# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_buffer'

module NewRelic
  module Agent
    class ErrorEventAggregator
      EVENT_TYPE = "TransactionError".freeze

      def initialize
        @lock = Mutex.new
        #capacity will come from config
        @error_event_buffer = SampledBuffer.new(100)
      end

      def append_event noticed_error, transaction_payload
        @lock.synchronize do
          @error_event_buffer.append_event do
            event_for_collector(noticed_error, transaction_payload)
          end
        end
      end

      def event_for_collector noticed_error, transaction_payload
        [
          intrinsic_attributes_for(noticed_error, transaction_payload),
          {},
          {}
        ]
      end

      def intrinsic_attributes_for noticed_error, transaction_payload
        attrs = {
          :type => EVENT_TYPE,
          :errorClass => noticed_error.exception_class_name,
          :errorMessage => noticed_error.message,
          :timestamp => noticed_error.timestamp.to_f,
          :transactionName => transaction_payload[:name],
          :transactionDuration => transaction_payload[:duration]
        }

        attrs[:'nr.syntheticsResourceId'] = transaction_payload[:synthetics_resource_id] if transaction_payload[:synthetics_resource_id]
        attrs[:'nr.syntheticsJobId'] = transaction_payload[:synthetics_job_id] if transaction_payload[:synthetics_job_id]
        attrs[:'nr.syntheticsMonitorId'] = transaction_payload[:synthetics_monitor_id] if transaction_payload[:synthetics_monitor_id]

        attrs
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
