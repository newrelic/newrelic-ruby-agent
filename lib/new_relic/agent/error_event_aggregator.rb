# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_buffer'
require 'new_relic/agent/payload_metric_mapping'

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

      private

      def event_for_collector noticed_error, transaction_payload
        [
          intrinsic_attributes_for(noticed_error, transaction_payload),
          noticed_error.custom_attributes,
          noticed_error.agent_attributes
        ]
      end

      def intrinsic_attributes_for noticed_error, transaction_payload
        attrs = {
          :type => EVENT_TYPE,
          :'error.class' => noticed_error.exception_class_name,
          :'error.message' => noticed_error.message,
          :timestamp => noticed_error.timestamp.to_f,
          :transactionName => transaction_payload[:name],
          :duration => transaction_payload[:duration]
        }

        append_synthetics transaction_payload, attrs
        append_cat transaction_payload, attrs
        PayloadMetricMapping.append_mapped_metrics transaction_payload[:metrics], attrs

        attrs
      end

      def append_synthetics transaction_payload, sample
        sample[:'nr.syntheticsResourceId'] = transaction_payload[:synthetics_resource_id] if transaction_payload[:synthetics_resource_id]
        sample[:'nr.syntheticsJobId'] = transaction_payload[:synthetics_job_id] if transaction_payload[:synthetics_job_id]
        sample[:'nr.syntheticsMonitorId'] = transaction_payload[:synthetics_monitor_id] if transaction_payload[:synthetics_monitor_id]
      end

      def append_cat transaction_payload, sample
        sample[:'nr.transactionGuid'] = transaction_payload[:guid] if transaction_payload[:guid]
        sample[:'nr.referringTransactionGuid'] = transaction_payload[:referring_transaction_guid] if transaction_payload[:referring_transaction_guid]
      end
    end
  end
end
