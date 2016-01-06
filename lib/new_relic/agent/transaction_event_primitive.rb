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

      # The type field of the sample
      SAMPLE_TYPE              = 'Transaction'.freeze

      # Strings for static keys of the sample structure
      TYPE_KEY                       = 'type'.freeze
      TIMESTAMP_KEY                  = 'timestamp'.freeze
      NAME_KEY                       = 'name'.freeze
      DURATION_KEY                   = 'duration'.freeze
      ERROR_KEY                      = 'error'.freeze
      GUID_KEY                       = 'nr.guid'.freeze
      REFERRING_TRANSACTION_GUID_KEY = 'nr.referringTransactionGuid'.freeze
      CAT_TRIP_ID_KEY                = 'nr.tripId'.freeze
      CAT_PATH_HASH_KEY              = 'nr.pathHash'.freeze
      CAT_REFERRING_PATH_HASH_KEY    = 'nr.referringPathHash'.freeze
      CAT_ALTERNATE_PATH_HASHES_KEY  = 'nr.alternatePathHashes'.freeze
      APDEX_PERF_ZONE_KEY            = 'nr.apdexPerfZone'.freeze
      SYNTHETICS_RESOURCE_ID_KEY     = "nr.syntheticsResourceId".freeze
      SYNTHETICS_JOB_ID_KEY          = "nr.syntheticsJobId".freeze
      SYNTHETICS_MONITOR_ID_KEY      = "nr.syntheticsMonitorId".freeze

      # To avoid allocations when we have empty custom or agent attributes
      EMPTY_HASH = {}.freeze

      def create(payload)
        intrinsics = {
        TIMESTAMP_KEY => float(payload[:start_timestamp]),
        NAME_KEY      => string(payload[:name]),
        DURATION_KEY  => float(payload[:duration]),
        TYPE_KEY      => SAMPLE_TYPE,
        ERROR_KEY     => payload[:error]
        }

        NewRelic::Agent::PayloadMetricMapping.append_mapped_metrics(payload[:metrics], intrinsics)
        append_optional_attributes(intrinsics, payload)

        attributes = payload[:attributes]

        [intrinsics, custom_attributes(attributes), agent_attributes(attributes)]
      end

      private

      def append_optional_attributes(sample, payload)
        optionally_append(GUID_KEY,                       :guid, sample, payload)
        optionally_append(REFERRING_TRANSACTION_GUID_KEY, :referring_transaction_guid, sample, payload)
        optionally_append(CAT_TRIP_ID_KEY,                :cat_trip_id, sample, payload)
        optionally_append(CAT_PATH_HASH_KEY,              :cat_path_hash, sample, payload)
        optionally_append(CAT_REFERRING_PATH_HASH_KEY,    :cat_referring_path_hash, sample, payload)
        optionally_append(APDEX_PERF_ZONE_KEY,            :apdex_perf_zone, sample, payload)
        optionally_append(SYNTHETICS_RESOURCE_ID_KEY,     :synthetics_resource_id, sample, payload)
        optionally_append(SYNTHETICS_JOB_ID_KEY,          :synthetics_job_id, sample, payload)
        optionally_append(SYNTHETICS_MONITOR_ID_KEY,      :synthetics_monitor_id, sample, payload)
        append_cat_alternate_path_hashes(sample, payload)
      end

      COMMA = ','.freeze

      def append_cat_alternate_path_hashes(sample, payload)
        if payload.include?(:cat_alternate_path_hashes)
          sample[CAT_ALTERNATE_PATH_HASHES_KEY] = payload[:cat_alternate_path_hashes].sort.join(COMMA)
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
