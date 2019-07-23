# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module DistributedTraceIntrinsics
      extend self

      # Intrinsic Keys
      PARENT_TYPE_INTRINSIC_KEY                = "parent.type".freeze
      PARENT_APP_INTRINSIC_KEY                 = "parent.app".freeze
      PARENT_ACCOUNT_ID_INTRINSIC_KEY          = "parent.account".freeze
      PARENT_TRANSPORT_TYPE_INTRINSIC_KEY      = "parent.transportType".freeze
      PARENT_TRANSPORT_DURATION_INTRINSIC_KEY  = "parent.transportDuration".freeze
      GUID_INTRINSIC_KEY                       = "guid".freeze
      TRACE_ID_INTRINSIC_KEY                   = "traceId".freeze
      PARENT_TRANSACTION_ID_INTRINSIC_KEY      = "parentId".freeze
      PARENT_SPAN_ID_INTRINSIC_KEY             = "parentSpanId".freeze
      SAMPLED_INTRINSIC_KEY                    = "sampled".freeze


      INTRINSIC_KEYS = [
        PARENT_TYPE_INTRINSIC_KEY,
        PARENT_APP_INTRINSIC_KEY,
        PARENT_ACCOUNT_ID_INTRINSIC_KEY,
        PARENT_TRANSPORT_TYPE_INTRINSIC_KEY,
        PARENT_TRANSPORT_DURATION_INTRINSIC_KEY,
        GUID_INTRINSIC_KEY,
        TRACE_ID_INTRINSIC_KEY,
        PARENT_TRANSACTION_ID_INTRINSIC_KEY,
        PARENT_SPAN_ID_INTRINSIC_KEY,
        SAMPLED_INTRINSIC_KEY
      ].freeze

      def assign_initial_intrinsics transaction, transaction_payload
        transaction_payload[GUID_INTRINSIC_KEY] = transaction.guid
        transaction_payload[TRACE_ID_INTRINSIC_KEY] = transaction.trace_id
        transaction_payload[SAMPLED_INTRINSIC_KEY] = transaction.sampled?
      end

      def assign_intrinsics transaction, distributed_trace_payload, transaction_payload
        transaction_payload[PARENT_TYPE_INTRINSIC_KEY] = distributed_trace_payload.parent_type
        transaction_payload[PARENT_APP_INTRINSIC_KEY] = distributed_trace_payload.parent_app_id
        transaction_payload[PARENT_ACCOUNT_ID_INTRINSIC_KEY] = distributed_trace_payload.parent_account_id
        transaction_payload[PARENT_TRANSPORT_TYPE_INTRINSIC_KEY] = valid_transport_type_for distributed_trace_payload.caller_transport_type
        transaction_payload[TRACE_ID_INTRINSIC_KEY] = distributed_trace_payload.trace_id
        if distributed_trace_payload.id
          transaction_payload[PARENT_SPAN_ID_INTRINSIC_KEY] = distributed_trace_payload.id
        end

        transaction_payload[PARENT_TRANSPORT_DURATION_INTRINSIC_KEY] = transaction.transport_duration
        transaction_payload[GUID_INTRINSIC_KEY] = transaction.guid
        if transaction.parent_transaction_id
          transaction_payload[PARENT_TRANSACTION_ID_INTRINSIC_KEY] = transaction.parent_transaction_id
        end
        transaction_payload[SAMPLED_INTRINSIC_KEY] = transaction.sampled?
      end

      PARENT_TRANSPORT_TYPE_UNKNOWN = 'Unknown'.freeze

      ALLOWABLE_TRANSPORT_TYPES = Set.new(%w[
        Unknown
        HTTP
        HTTPS
        Kafka
        JMS
        IronMQ
        AMQP
        Queue
        Other
      ]).freeze

      def valid_transport_type_for(value)
        return value if ALLOWABLE_TRANSPORT_TYPES.include?(value)

        PARENT_TRANSPORT_TYPE_UNKNOWN
      end

    end
  end
end