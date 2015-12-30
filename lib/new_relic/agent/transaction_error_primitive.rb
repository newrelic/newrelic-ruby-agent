# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module was introduced and largely extracted from the transaction event aggregator
# when the synthetics container was extracted from it. Its purpose is to create the data
# necessary for creating a transaction event and to facilitate transfer of events between
# the transaction event aggregator and the synthetics container.

require 'new_relic/agent/payload_metric_mapping'

module NewRelic
  module Agent
    module TransactionErrorPrimitive
      extend self

      def create noticed_error, payload
        [
          intrinsic_attributes_for(noticed_error, payload),
          noticed_error.custom_attributes,
          noticed_error.agent_attributes
        ]
      end

      def intrinsic_attributes_for noticed_error, payload
        attrs = {
          :type => :TransactionError,
          :'error.class' => noticed_error.exception_class_name,
          :'error.message' => noticed_error.message,
          :timestamp => noticed_error.timestamp.to_f
        }

        attrs[:port] = noticed_error.request_port if noticed_error.request_port

        if payload
          attrs[:transactionName] = payload[:name]
          attrs[:duration] = payload[:duration]
          append_synthetics payload, attrs
          append_cat payload, attrs
          PayloadMetricMapping.append_mapped_metrics payload[:metrics], attrs
        end

        attrs
      end

      def append_synthetics payload, sample
        sample[:'nr.syntheticsResourceId'] = payload[:synthetics_resource_id] if payload[:synthetics_resource_id]
        sample[:'nr.syntheticsJobId'] = payload[:synthetics_job_id] if payload[:synthetics_job_id]
        sample[:'nr.syntheticsMonitorId'] = payload[:synthetics_monitor_id] if payload[:synthetics_monitor_id]
      end

      def append_cat payload, sample
        sample[:'nr.transactionGuid'] = payload[:guid] if payload[:guid]
        sample[:'nr.referringTransactionGuid'] = payload[:referring_transaction_guid] if payload[:referring_transaction_guid]
      end
    end
  end
end
