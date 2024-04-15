# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This module was introduced and largely extracted from the transaction event aggregator
# when the synthetics container was extracted from it. Its purpose is to create the data
# necessary for creating a transaction event and to facilitate transfer of events between
# the transaction event aggregator and the synthetics container.

require 'new_relic/agent/payload_metric_mapping'
require 'new_relic/agent/distributed_tracing/distributed_trace_payload'
require 'new_relic/agent/distributed_tracing/distributed_trace_attributes'

module NewRelic
  module Agent
    module TransactionErrorPrimitive
      extend self

      SAMPLE_TYPE = 'TransactionError'
      TYPE_KEY = 'type'
      ERROR_CLASS_KEY = 'error.class'
      ERROR_MESSAGE_KEY = 'error.message'
      ERROR_EXPECTED_KEY = 'error.expected'
      TIMESTAMP_KEY = 'timestamp'
      PORT_KEY = 'port'
      NAME_KEY = 'transactionName'
      DURATION_KEY = 'duration'
      SAMPLED_KEY = 'sampled'
      CAT_GUID_KEY = 'nr.transactionGuid'
      CAT_REFERRING_TRANSACTION_GUID_KEY = 'nr.referringTransactionGuid'
      SYNTHETICS_RESOURCE_ID_KEY = 'nr.syntheticsResourceId'
      SYNTHETICS_JOB_ID_KEY = 'nr.syntheticsJobId'
      SYNTHETICS_MONITOR_ID_KEY = 'nr.syntheticsMonitorId'
      SYNTHETICS_TYPE_KEY = 'nr.syntheticsType'
      SYNTHETICS_INITIATOR_KEY = 'nr.syntheticsInitiator'
      SYNTHETICS_KEY_PREFIX = 'nr.synthetics'
      PRIORITY_KEY = 'priority'
      SPAN_ID_KEY = 'spanId'
      GUID_KEY = 'guid'

      SYNTHETICS_PAYLOAD_EXPECTED = [:synthetics_resource_id, :synthetics_job_id, :synthetics_monitor_id, :synthetics_type, :synthetics_initiator]

      def create(noticed_error, payload, span_id)
        [
          intrinsic_attributes_for(noticed_error, payload, span_id),
          noticed_error.custom_attributes,
          noticed_error.agent_attributes
        ]
      end

      def intrinsic_attributes_for(noticed_error, payload, span_id)
        attrs = {
          TYPE_KEY => SAMPLE_TYPE,
          ERROR_CLASS_KEY => noticed_error.exception_class_name,
          ERROR_MESSAGE_KEY => noticed_error.message,
          ERROR_EXPECTED_KEY => noticed_error.expected,
          TIMESTAMP_KEY => noticed_error.timestamp.to_f
        }

        attrs[SPAN_ID_KEY] = span_id if span_id
        # don't use safe navigation - leave off keys with missing values
        # instead of using nil
        attrs[PORT_KEY] = noticed_error.request_port if noticed_error.request_port
        attrs[GUID_KEY] = noticed_error.transaction_id if noticed_error.transaction_id

        if payload
          attrs[NAME_KEY] = payload[:name]
          attrs[DURATION_KEY] = payload[:duration]
          attrs[SAMPLED_KEY] = payload[:sampled] if payload.key?(:sampled)
          attrs[PRIORITY_KEY] = payload[:priority]
          append_synthetics(payload, attrs)
          append_cat(payload, attrs)
          DistributedTraceAttributes.copy_to_hash(payload, attrs)
          PayloadMetricMapping.append_mapped_metrics(payload[:metrics], attrs)
        else
          attrs[PRIORITY_KEY] = rand.round(NewRelic::PRIORITY_PRECISION)
        end

        attrs
      end

      def append_synthetics(payload, sample)
        return unless payload[:synthetics_job_id]

        sample[SYNTHETICS_RESOURCE_ID_KEY] = payload[:synthetics_resource_id] if payload[:synthetics_resource_id]
        sample[SYNTHETICS_JOB_ID_KEY] = payload[:synthetics_job_id] if payload[:synthetics_job_id]
        sample[SYNTHETICS_MONITOR_ID_KEY] = payload[:synthetics_monitor_id] if payload[:synthetics_monitor_id]
        sample[SYNTHETICS_TYPE_KEY] = payload[:synthetics_type] if payload[:synthetics_type]
        sample[SYNTHETICS_INITIATOR_KEY] = payload[:synthetics_initiator] if payload[:synthetics_initiator]

        payload.each do |k, v|
          next unless k.to_s.start_with?('synthetics_') && !SYNTHETICS_PAYLOAD_EXPECTED.include?(k)

          new_key = SYNTHETICS_KEY_PREFIX + NewRelic::LanguageSupport.camelize(k.to_s.gsub('synthetics_', ''))
          sample[new_key] = v
        end
      end

      def append_cat(payload, sample)
        sample[CAT_GUID_KEY] = payload[:guid] if payload[:guid]
        sample[CAT_REFERRING_TRANSACTION_GUID_KEY] = payload[:referring_transaction_guid] if payload[:referring_transaction_guid]
      end
    end
  end
end
