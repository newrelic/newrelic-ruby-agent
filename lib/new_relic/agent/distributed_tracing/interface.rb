# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module DistributedTracing
      RABBITMQ_TRANSPORT_TYPE = "RabbitMQ"
      NEWRELIC_HEADER         = "newrelic"
      CANDIDATE_HEADERS       = [
        NEWRELIC_HEADER, 
        'NEWRELIC', 
        'NewRelic',
        'Newrelic'
      ].freeze

      class Interface

        def nr_distributed_tracing_enabled?
          Agent.config[:'distributed_tracing.enabled'] && 
          (Agent.config[:'distributed_tracing.format'] == NEWRELIC_HEADER)
        end

        def nr_distributed_tracing_active?
          nr_distributed_tracing_enabled? && Agent.instance.connected?
        end

        def insert_headers transaction, request
          if transaction.trace_context_enabled?
            insert_trace_context_headers transaction, request
          elsif nr_distributed_tracing_active?
            insert_distributed_trace_header transaction, request
          elsif CrossAppTracing.cross_app_enabled?
            insert_cross_app_header transaction, request
          end
        end

        def consume_headers transaction, headers, state
          consume_distributed_tracing_headers headers, transaction
          consume_cross_app_tracing_headers headers, state
          consume_synthetics_headers headers, transaction
        # rescue => e
        #   NewRelic::Agent.logger.error "Error in consume_message_headers", e
        end

        private 

        def consume_synthetics_headers headers, transaction
          synthetics_header = headers[CrossAppTracing::NR_MESSAGE_BROKER_SYNTHETICS_HEADER]
          if synthetics_header and
             incoming_payload = ::JSON.load(CrossAppTracing.obfuscator.deobfuscate(synthetics_header)) and
             SyntheticsMonitor.is_valid_payload?(incoming_payload) and
             SyntheticsMonitor.is_supported_version?(incoming_payload) and
             SyntheticsMonitor.is_trusted?(incoming_payload)

            transaction.raw_synthetics_header = synthetics_header
            transaction.synthetics_payload = incoming_payload
          end
        # rescue => e
        #   NewRelic::Agent.logger.error "Error in assign_synthetics_header", e
        end

        def consume_distributed_tracing_headers headers, transaction
          return unless Agent.config[:'distributed_tracing.enabled']
          return unless newrelic_trace_key = CANDIDATE_HEADERS.detect do |key|
            headers.has_key?(key)
          end

          return unless payload = headers[newrelic_trace_key]

          if transaction.accept_distributed_trace_payload payload
            transaction.distributed_trace_payload.caller_transport_type = RABBITMQ_TRANSPORT_TYPE
          end
        end

        def consume_cross_app_tracing_headers headers, state
          if CrossAppTracing.cross_app_enabled? && CrossAppTracing.message_has_crossapp_request_header?(headers)
            decode_txn_info headers, state
            CrossAppTracing.assign_intrinsic_transaction_attributes state
          end
        end

        def decode_txn_info headers, transaction_state
          encoded_id = headers[CrossAppTracing::NR_MESSAGE_BROKER_ID_HEADER]

          decoded_id = if encoded_id.nil?
                         EMPTY_STRING
                       else
                         CrossAppTracing.obfuscator.deobfuscate(encoded_id)
                       end

          if CrossAppTracing.trusted_valid_cross_app_id?(decoded_id) && transaction_state.current_transaction
            txn_header = headers[CrossAppTracing::NR_MESSAGE_BROKER_TXN_HEADER]
            txn        = transaction_state.current_transaction
            txn_info   = ::JSON.load(CrossAppTracing.obfuscator.deobfuscate(txn_header))
            payload    = CrossAppPayload.new(decoded_id, txn, txn_info)

            txn.cross_app_payload = payload
          end
        # rescue => e
        #   NewRelic::Agent.logger.debug("Failure deserializing encoded header in #{self.class}, #{e.class}, #{e.message}")
        #   nil
        end

        def insert_cross_app_header transaction, request
          transaction.is_cross_app_caller = true
          txn_guid = transaction.guid
          trip_id   = transaction && transaction.cat_trip_id
          path_hash = transaction && transaction.cat_path_hash

          CrossAppTracing.insert_request_headers request, txn_guid, trip_id, path_hash
        end

        def insert_trace_context_headers transaction, request
          transaction.insert_trace_context carrier: request
        end

        def insert_distributed_trace_header transaction, request
          payload = transaction.create_distributed_trace_payload
          request[NEWRELIC_HEADER] = payload.http_safe if payload
        end

      end
    end
  end
end