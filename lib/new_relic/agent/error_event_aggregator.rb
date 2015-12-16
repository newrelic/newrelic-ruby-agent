# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/payload_metric_mapping'

module NewRelic
  module Agent
    class ErrorEventAggregator < EventAggregator
      EVENT_TYPE = "TransactionError".freeze

      named :ErrorEventAggregator

      capacity_key :'error_collector.max_event_samples_stored'

      enabled_key :'error_collector.capture_events'

      def append_event noticed_error, transaction_payload = nil
        return unless enabled?

        @lock.synchronize do
          @buffer.append do
            event_for_collector(noticed_error, transaction_payload)
          end

          notify_if_full
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
          :timestamp => noticed_error.timestamp.to_f
        }

        attrs[:port] = noticed_error.request_port if noticed_error.request_port

        if transaction_payload
          attrs[:transactionName] = transaction_payload[:name]
          attrs[:duration] = transaction_payload[:duration]
          append_synthetics transaction_payload, attrs
          append_cat transaction_payload, attrs
          PayloadMetricMapping.append_mapped_metrics transaction_payload[:metrics], attrs
        end

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
