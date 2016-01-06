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
    module TransactionEventPrimitive
      include NewRelic::Coerce
      extend self

      # To avoid allocations when we have empty custom or agent attributes
      EMPTY_HASH = {}.freeze
      # Always use string representation of timestamp since the SyntheticsEventBuffer
      # checks the 'timestamp' value for admission into its buffer
      TIMESTAMP = "timestamp".freeze

      def create(payload)
        intrinsics = {
        TIMESTAMP => float(payload[:start_timestamp]),
        :name     => string(payload[:name]),
        :duration  => float(payload[:duration]),
        :type     => :Transaction,
        :error     => payload[:error]
        }

        NewRelic::Agent::PayloadMetricMapping.append_mapped_metrics(payload[:metrics], intrinsics)
        append_optional_attributes(intrinsics, payload)

        attributes = payload[:attributes]

        [intrinsics, custom_attributes(attributes), agent_attributes(attributes)]
      end

      private

      def append_optional_attributes(sample, payload)
        optionally_append(:'nr.guid',                       :guid, sample, payload)
        optionally_append(:'nr.referringTransactionGuid', :referring_transaction_guid, sample, payload)
        optionally_append(:'nr.tripId',                :cat_trip_id, sample, payload)
        optionally_append(:'nr.pathHash',              :cat_path_hash, sample, payload)
        optionally_append(:'nr.referringPathHash',    :cat_referring_path_hash, sample, payload)
        optionally_append(:'nr.apdexPerfZone',            :apdex_perf_zone, sample, payload)
        optionally_append(:'nr.syntheticsResourceId',     :synthetics_resource_id, sample, payload)
        optionally_append(:'nr.syntheticsJobId',          :synthetics_job_id, sample, payload)
        optionally_append(:'nr.syntheticsMonitorId',      :synthetics_monitor_id, sample, payload)
        append_cat_alternate_path_hashes(sample, payload)
      end

      COMMA = ','.freeze

      def append_cat_alternate_path_hashes(sample, payload)
        if payload.include?(:cat_alternate_path_hashes)
          sample[:'nr.alternatePathHashes'] = payload[:cat_alternate_path_hashes].sort.join(COMMA)
        end
      end

      def optionally_append(sample_key, payload_key, sample, payload)
        if payload.include?(payload_key)
          sample[sample_key] = string(payload[payload_key])
        end
      end

      def custom_attributes attributes
        if attributes
          result = attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
          result.freeze
        else
          EMPTY_HASH
        end
      end

      def agent_attributes attributes
        if attributes
          result = attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
          result.freeze
        else
          EMPTY_HASH
        end
      end
    end
  end
end
