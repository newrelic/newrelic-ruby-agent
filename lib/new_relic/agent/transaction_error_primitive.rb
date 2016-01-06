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

      SAMPLE_TYPE                    = 'TransactionError'.freeze
      TYPE_KEY                       = 'type'.freeze
      ERROR_CLASS_KEY                = 'error.class'.freeze
      ERROR_MESSAGE_KEY              = 'error.message'.freeze
      TIMESTAMP_KEY                  = 'timestamp'.freeze
      PORT_KEY                       = 'port'.freeze
      NAME_KEY                       = 'transactionName'.freeze
      DURATION_KEY                   = 'duration'.freeze
      GUID_KEY                       = 'nr.transactionGuid'.freeze
      REFERRING_TRANSACTION_GUID_KEY = 'nr.referringTransactionGuid'.freeze
      SYNTHETICS_RESOURCE_ID_KEY     = "nr.syntheticsResourceId".freeze
      SYNTHETICS_JOB_ID_KEY          = "nr.syntheticsJobId".freeze
      SYNTHETICS_MONITOR_ID_KEY      = "nr.syntheticsMonitorId".freeze

      def create noticed_error, payload
        [
          intrinsic_attributes_for(noticed_error, payload),
          noticed_error.custom_attributes,
          noticed_error.agent_attributes
        ]
      end

      def intrinsic_attributes_for noticed_error, payload
        attrs = {
          TYPE_KEY => SAMPLE_TYPE,
          ERROR_CLASS_KEY => noticed_error.exception_class_name,
          ERROR_MESSAGE_KEY => noticed_error.message,
          TIMESTAMP_KEY => noticed_error.timestamp.to_f
        }

        attrs[PORT_KEY] = noticed_error.request_port if noticed_error.request_port

        if payload
          attrs[NAME_KEY] = payload[:name]
          attrs[DURATION_KEY] = payload[:duration]
          append_synthetics payload, attrs
          append_cat payload, attrs
          PayloadMetricMapping.append_mapped_metrics payload[:metrics], attrs
        end

        attrs
      end

      def append_synthetics payload, sample
        sample[SYNTHETICS_RESOURCE_ID_KEY] = payload[:synthetics_resource_id] if payload[:synthetics_resource_id]
        sample[SYNTHETICS_JOB_ID_KEY] = payload[:synthetics_job_id] if payload[:synthetics_job_id]
        sample[SYNTHETICS_MONITOR_ID_KEY] = payload[:synthetics_monitor_id] if payload[:synthetics_monitor_id]
      end

      def append_cat payload, sample
        sample[GUID_KEY] = payload[:guid] if payload[:guid]
        sample[REFERRING_TRANSACTION_GUID_KEY] = payload[:referring_transaction_guid] if payload[:referring_transaction_guid]
      end
    end
  end
end
