# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/transaction/trace_context'
require 'new_relic/agent/transaction/distributed_tracing'
require 'new_relic/agent/distributed_tracing/cross_app_tracing'

module NewRelic
  module Agent
    class Transaction
      class DistributedTracer
        W3C_FORMAT        = "w3c" # TODO: REMOVE?
        NEWRELIC_HEADER   = "newrelic"
        CANDIDATE_HEADERS = [
          NEWRELIC_HEADER,
          'NEWRELIC',
          'NewRelic',
          'Newrelic'
        ].freeze

        include NewRelic::Agent::CrossAppTracing
        include DistributedTracing
        include TraceContext

        attr_reader :transaction

        def initialize transaction
          @transaction = transaction
        end

        def record_metrics
          record_cross_app_metrics
          DistributedTraceMetrics.record_metrics_for_transaction transaction
        end

        def append_payload payload
          append_cat_info payload
          append_distributed_trace_info payload
          append_trace_context_info payload
        end

        def insert_headers request
          if trace_context_active?
            insert_trace_context_headers request
          elsif nr_distributed_tracing_active?
            insert_distributed_trace_header request
          elsif CrossAppTracing.cross_app_enabled?
            insert_cross_app_header request
          end
        end

        def consume_headers headers, tracer_state
          consume_distributed_tracing_headers headers
          consume_cross_app_tracing_headers headers, tracer_state
          consume_synthetics_headers headers
        rescue => e
          NewRelic::Agent.logger.error "Error in consume_message_headers", e
        end

        def assign_intrinsics
          if Agent.config[:'distributed_tracing.enabled'] || trace_context_active?
            DistributedTraceIntrinsics.copy_to_attributes transaction.payload, transaction.attributes
          elsif is_cross_app?
            assign_cross_app_intrinsics
          end
        end

        private

        def consume_synthetics_headers headers
          synthetics_header = headers[CrossAppTracing::NR_MESSAGE_BROKER_SYNTHETICS_HEADER]
          if synthetics_header and
             incoming_payload = ::JSON.load(obfuscator.deobfuscate(synthetics_header)) and
             SyntheticsMonitor.is_valid_payload?(incoming_payload) and
             SyntheticsMonitor.is_supported_version?(incoming_payload) and
             SyntheticsMonitor.is_trusted?(incoming_payload)

            transaction.raw_synthetics_header = synthetics_header
            transaction.synthetics_payload = incoming_payload
          end
        rescue => e
          NewRelic::Agent.logger.error "Error in assign_synthetics_header", e
        end

        def consume_distributed_tracing_headers headers
          return unless Agent.config[:'distributed_tracing.enabled']
          return unless newrelic_trace_key = CANDIDATE_HEADERS.detect do |key|
            headers.has_key?(key)
          end

          return unless payload = headers[newrelic_trace_key]

          if accept_distributed_trace_payload payload
            distributed_trace_payload.caller_transport_type = RABBITMQ_TRANSPORT_TYPE
          end
        end

        def consume_cross_app_tracing_headers headers, tracer_state
          if CrossAppTracing.cross_app_enabled? && CrossAppTracing.message_has_crossapp_request_header?(headers)
            decode_txn_info headers, tracer_state
            CrossAppTracing.assign_intrinsic_transaction_attributes tracer_state
          end
        end

        def decode_txn_info headers, tracer_state
          encoded_id = headers[CrossAppTracing::NR_MESSAGE_BROKER_ID_HEADER]
          decoded_id = encoded_id.nil? ? EMPTY_STRING : obfuscator.deobfuscate(encoded_id)

          if CrossAppTracing.trusted_valid_cross_app_id?(decoded_id) && tracer_state.current_transaction
            txn_header = headers[CrossAppTracing::NR_MESSAGE_BROKER_TXN_HEADER]
            txn        = tracer_state.current_transaction
            txn_info   = ::JSON.load(CrossAppTracing.obfuscator.deobfuscate(txn_header))
            payload    = CrossAppPayload.new(decoded_id, txn, txn_info)

            txn.distributed_tracer.cross_app_payload = payload
          end
        rescue => e
          NewRelic::Agent.logger.debug("Failure deserializing encoded header in #{self.class}, #{e.class}, #{e.message}")
          nil
        end

        def insert_trace_context_headers request
          insert_trace_context carrier: request
        end

        def insert_distributed_trace_header request
          payload = create_distributed_trace_payload
          request[NEWRELIC_HEADER] = payload.http_safe if payload
        end

      end
    end
  end
end

