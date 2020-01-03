# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require_relative 'distributed_trace_transport_type'

module NewRelic
  module Agent
    module DistributedTraceIntrinsics
      extend self

      # Intrinsic Keys
      PARENT_TYPE_KEY                = "parent.type".freeze
      PARENT_APP_KEY                 = "parent.app".freeze
      PARENT_ACCOUNT_ID_KEY          = "parent.account".freeze
      PARENT_TRANSPORT_TYPE_KEY      = "parent.transportType".freeze
      PARENT_TRANSPORT_DURATION_KEY  = "parent.transportDuration".freeze
      GUID_KEY                       = "guid".freeze
      TRACE_ID_KEY                   = "traceId".freeze
      PARENT_TRANSACTION_ID_KEY      = "parentId".freeze
      PARENT_SPAN_ID_KEY             = "parentSpanId".freeze
      SAMPLED_KEY                    = "sampled".freeze

      INTRINSIC_KEYS = [
        PARENT_TYPE_KEY,
        PARENT_APP_KEY,
        PARENT_ACCOUNT_ID_KEY,
        PARENT_TRANSPORT_TYPE_KEY,
        PARENT_TRANSPORT_DURATION_KEY,
        GUID_KEY,
        TRACE_ID_KEY,
        PARENT_TRANSACTION_ID_KEY,
        PARENT_SPAN_ID_KEY,
        SAMPLED_KEY
      ].freeze

      # This method extracts intrinsics from the transaction_payload and
      # inserts them into the specified destination.
      def copy_to_hash transaction_payload, destination
        return unless enabled?
        INTRINSIC_KEYS.each do |key|
          value = transaction_payload[key]
          destination[key] = value unless value.nil?
        end
      end

      # This method extracts intrinsics from the transaction_payload and
      # inserts them as intrinsics in the specified transaction_attributes
      def copy_to_attributes transaction_payload, destination
        return unless enabled?
        INTRINSIC_KEYS.each do |key|
          next unless transaction_payload.key? key
          destination.add_intrinsic_attribute key, transaction_payload[key]
        end
      end

      # This method takes all distributed tracing intrinsics from the transaction
      # and the distributed_trace_payload, and populates them into the destination
      def copy_from_transaction transaction, distributed_trace_payload, destination
        destination[GUID_KEY] = transaction.guid
        destination[SAMPLED_KEY] = transaction.sampled?
        destination[TRACE_ID_KEY] = transaction.trace_id

        if transaction.parent_span_id
          destination[PARENT_SPAN_ID_KEY] = transaction.parent_span_id
        end

        if distributed_trace_payload
          destination[PARENT_TYPE_KEY] = distributed_trace_payload.parent_type
          destination[PARENT_APP_KEY] = distributed_trace_payload.parent_app_id
          destination[PARENT_ACCOUNT_ID_KEY] = distributed_trace_payload.parent_account_id
          destination[PARENT_TRANSPORT_TYPE_KEY] = DistributedTraceTransportType.from distributed_trace_payload.caller_transport_type

          destination[PARENT_TRANSPORT_DURATION_KEY] = transaction.calculate_transport_duration distributed_trace_payload

          if transaction.parent_transaction_id
            destination[PARENT_TRANSACTION_ID_KEY] = transaction.parent_transaction_id
          end
        end
      end

      private

      def enabled?
        return Agent.config[:'distributed_tracing.enabled']
      end

    end
  end
end
