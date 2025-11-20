# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/transaction/trace_context'
require 'new_relic/agent/transaction/distributed_tracing'

module NewRelic
  module Agent
    class Transaction
      class DistributedTracer
        include DistributedTracing
        include TraceContext

        attr_reader :transaction
        attr_accessor :parent_transaction_id

        def parent_guid
          if trace_context_header_data
            trace_context_header_data.parent_id
          elsif distributed_trace_payload
            distributed_trace_payload.id
          end
        end

        def accept_incoming_request(request, transport_type = nil)
          accept_incoming_transport_type(request, transport_type)
          if trace_parent_header_present?(request)
            accept_trace_context_incoming_request(request)
          else
            accept_distributed_tracing_incoming_request(request)
          end
        end

        def caller_transport_type
          @caller_transport_type ||= NewRelic::UNKNOWN
        end

        def accept_transport_type_from_api(value)
          @caller_transport_type = DistributedTraceTransportType.from(value)
        end

        def accept_incoming_transport_type(request, transport_type)
          if transport_type.to_s == NewRelic::EMPTY_STR
            @caller_transport_type = DistributedTraceTransportType.for_rack_request(request)
          else
            @caller_transport_type = DistributedTraceTransportType.from(transport_type)
          end
        end

        def initialize(transaction)
          @transaction = transaction
        end

        def record_metrics
          DistributedTraceMetrics.record_metrics_for_transaction(transaction)
        end

        def append_payload(payload)
          DistributedTraceAttributes.copy_from_transaction( \
            transaction,
            trace_state_payload || distributed_trace_payload,
            payload
          )
        end

        def log_request_headers(headers, direction = 'OUTGOING')
          printed_headers = headers.is_a?(NewRelic::Agent::HTTPClients::AbstractRequest) ? headers.headers : headers
          NewRelic::Agent.logger.debug("#{direction} REQUEST HEADERS: #{printed_headers}")
        end

        def insert_headers(headers)
          return unless NewRelic::Agent.agent.connected?

          insert_trace_context_header(headers)
          insert_distributed_trace_header(headers)
          log_request_headers(headers)
        end

        def consume_message_headers(headers, tracer_state, transport_type)
          log_request_headers(headers, 'INCOMING')
          consume_message_distributed_tracing_headers(headers, transport_type)
          consume_message_synthetics_headers(headers)
        rescue => e
          NewRelic::Agent.logger.error('Error in consume_message_headers', e)
        end

        def assign_intrinsics
          if dt_enabled?
            DistributedTraceAttributes.copy_to_attributes(transaction.payload, transaction.attributes)
          end
        end

        def insert_distributed_trace_header(headers)
          return unless dt_enabled?
          return if Agent.config[:'exclude_newrelic_header']

          payload = create_distributed_trace_payload
          headers[NewRelic::NEWRELIC_KEY] = payload.http_safe if payload
        end

        private

        def dt_enabled?
          Agent.config[:'distributed_tracing.enabled']
        end

        def consume_message_synthetics_headers(headers)
          synthetics_header = headers[SyntheticsMonitor::NON_HTTP_SYNTHETICS_HEADER_KEY]
          if synthetics_header
            require 'new_relic/agent/obfuscator'
            obfuscator = ::NewRelic::Agent::Obfuscator.new(Agent.config[:encoding_key])
            incoming_payload = ::JSON.parse(obfuscator.deobfuscate(synthetics_header))
            if SyntheticsMonitor.is_valid_payload?(incoming_payload) &&
                SyntheticsMonitor.is_supported_version?(incoming_payload) &&
                SyntheticsMonitor.is_trusted?(incoming_payload)

              transaction.raw_synthetics_header = synthetics_header
              transaction.synthetics_payload = incoming_payload
            end
          end
        rescue => e
          NewRelic::Agent.logger.error('Error in consume_message_synthetics_header', e)
        end

        def consume_message_distributed_tracing_headers(headers, transport_type)
          return unless dt_enabled?

          accept_incoming_transport_type(headers, transport_type)

          newrelic_trace_key = NewRelic::CANDIDATE_NEWRELIC_KEYS.detect do |key|
            headers.has_key?(key)
          end
          return unless newrelic_trace_key && (payload = headers[newrelic_trace_key])

          accept_distributed_trace_payload(payload)
        end
      end
    end
  end
end
