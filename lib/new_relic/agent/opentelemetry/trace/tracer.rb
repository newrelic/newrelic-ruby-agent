# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class Tracer < ::OpenTelemetry::Trace::Tracer
          def initialize(name = nil, version = nil)
            @name = name || ''
            @version = version || ''
          end

          def start_span(name, with_parent: nil, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
            parent_otel_context = ::OpenTelemetry::Trace.current_span(with_parent).context

            finishable = if can_start_transaction?(parent_otel_context)
              return if internal_span_kind_with_invalid_parent?(kind, parent_otel_context)

              nr_item = NewRelic::Agent::Tracer.start_transaction_or_segment(name: name, category: :otel)

              add_remote_context_to_txn(nr_item, parent_otel_context)

              nr_item
            else
              NewRelic::Agent::Tracer.start_segment(name: name)
            end

            otel_span = get_otel_span_from_finishable(finishable)
            otel_span.finishable = finishable
            add_remote_context_to_otel_span(otel_span, parent_otel_context)
            otel_span.add_attributes(attributes) if attributes
            otel_span
          end

          def in_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
            span = start_span(name, attributes: attributes, links: links, start_timestamp: start_timestamp, kind: kind)
            begin
              yield
            rescue => e
              # TODO: Update for segment errors if finishable is a segment
              NewRelic::Agent.notice_error(e)
              raise
            end
          ensure
            span&.finish
          end

          private

          def get_otel_span_from_finishable(finishable)
            case finishable
            when NewRelic::Agent::Transaction
              finishable.segments.first.instance_variable_get(:@otel_span)
            when NewRelic::Agent::Transaction::Segment
              finishable.instance_variable_get(:@otel_span)
            else
              NewRelic::Agent.logger.warn('Tracer#get_otel_span_from_finishable failed to get span from finishable - finishable is not a transaction or segment')
              nil
            end
          end

          def can_start_transaction?(parent_otel_context)
            parent_otel_context.remote? || !parent_otel_context.valid?
          end

          def internal_span_kind_with_invalid_parent?(kind, parent_otel_context)
            !parent_otel_context.valid? && kind == :internal
          end

          def transaction_and_remote_parent?(txn, parent_otel_context)
            txn.is_a?(NewRelic::Agent::Transaction) && parent_otel_context.remote?
          end

          def add_remote_context_to_txn(txn, parent_otel_context)
            return unless transaction_and_remote_parent?(txn, parent_otel_context)

            txn.trace_id = parent_otel_context.trace_id
            txn.parent_span_id = parent_otel_context.span_id

            set_tracestate(txn.distributed_tracer, parent_otel_context)
          end

          def set_tracestate(distributed_tracer, otel_context)
            case otel_context.tracestate
            when ::OpenTelemetry::Trace::Tracestate
              set_otel_trace_state(distributed_tracer, otel_context)
            when NewRelic::Agent::TraceContextPayload
              set_nr_trace_state(distributed_tracer, otel_context)
            end
          end

          def set_nr_trace_state(distributed_tracer, otel_context)
            distributed_tracer.instance_variable_set(:@trace_state_payload, otel_context.tracestate)
            distributed_tracer.parent_transaction_id = distributed_tracer.trace_state_payload.transaction_id
            trace_flags = parse_trace_flags(otel_context.trace_flags)

            distributed_tracer.determine_sampling_decision(otel_context.tracestate, trace_flags)
          end

          def set_otel_trace_state(distributed_tracer, otel_context)
            nr_entry = otel_context.tracestate.value(Transaction::TraceContext::AccountHelpers.trace_state_entry_key)
            trace_flags = parse_trace_flags(otel_context.trace_flags)

            if nr_entry
              nr_payload = NewRelic::Agent::TraceContextPayload.from_s(nr_entry)

              distributed_tracer.instance_variable_set(:@trace_state_payload, nr_payload)
              distributed_tracer.parent_transaction_id = distributed_tracer.trace_state_payload.transaction_id
              distributed_tracer.determine_sampling_decision(nr_payload, trace_flags)
            else
              distributed_tracer.determine_sampling_decision(NewRelic::Agent::TraceContextPayload::INVALID, trace_flags)
            end
          end

          def parse_trace_flags(trace_flags)
            case trace_flags
            when String
              trace_flags
            when Integer
              trace_flags.to_s
            when ::OpenTelemetry::Trace::TraceFlags
              trace_flags.sampled? ? '01' : '00'
            end
          end

          def add_remote_context_to_otel_span(otel_span, parent_otel_context)
            return unless transaction_and_remote_parent?(otel_span.finishable, parent_otel_context)

            otel_span.context.instance_variable_set(:@trace_id, otel_span.finishable.trace_id)
          end
        end
      end
    end
  end
end
