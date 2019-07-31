# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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

      def extract_to_hash transaction_payload, attributes_hash
        # This method extracts intrinsics from the transaction_payload and
        # inserts them into the specified attributes_hash.  
        return unless Agent.config[:'distributed_tracing.enabled']
        INTRINSIC_KEYS.each do |key|
          value = transaction_payload[key]
          attributes_hash[key] = value unless value.nil?
        end
      end

      def extract_to_transaction_attributes transaction_payload, transacton_attributes
        # This method extracts intrinsics from the transaction_payload and
        # inserts them as intrinsics in the specified transaction_attributes
        return unless Agent.config[:'distributed_tracing.enabled']
        INTRINSIC_KEYS.each do |key|
          next unless transaction_payload.key? key
          transacton_attributes.add_intrinsic_attribute key, transaction_payload[key]
        end
      end

      def add_to_transaction_payload transaction, distributed_trace_payload, transaction_payload
        # This method takes all distributed tracing intrinsics from the transaction
        # and the distributed_trace_payload, and populates them into the 
        # transaction payload
        transaction_payload[GUID_KEY] = transaction.guid
        transaction_payload[SAMPLED_KEY] = transaction.sampled?
 
        if distributed_trace_payload
          transaction_payload[TRACE_ID_KEY] = distributed_trace_payload.trace_id

          transaction_payload[PARENT_TYPE_KEY] = distributed_trace_payload.parent_type
          transaction_payload[PARENT_APP_KEY] = distributed_trace_payload.parent_app_id
          transaction_payload[PARENT_ACCOUNT_ID_KEY] = distributed_trace_payload.parent_account_id
          transaction_payload[PARENT_TRANSPORT_TYPE_KEY] = valid_transport_type_for distributed_trace_payload.caller_transport_type
          if distributed_trace_payload.id
            transaction_payload[PARENT_SPAN_ID_KEY] = distributed_trace_payload.id
          end

          transaction_payload[PARENT_TRANSPORT_DURATION_KEY] = transaction.transport_duration
          if transaction.parent_transaction_id
            transaction_payload[PARENT_TRANSACTION_ID_KEY] = transaction.parent_transaction_id
          end
        else
          transaction_payload[TRACE_ID_KEY] = transaction.trace_id
        end
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