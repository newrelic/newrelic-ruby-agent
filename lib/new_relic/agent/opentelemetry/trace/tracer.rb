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
            parent_span_context = ::OpenTelemetry::Trace.current_span(with_parent).context

            finishable = if can_start_transaction?(parent_span_context)
              return if internal_span_kind_with_invalid_parent?(kind, parent_span_context)

              nr_obj = NewRelic::Agent::Tracer.start_transaction_or_segment(name: name, category: :otel)
              add_remote_partent_span_context_to_txn(nr_obj, parent_span_context)
              nr_obj
            else
              NewRelic::Agent::Tracer.start_segment(name: name)
            end

            span = get_span_from_finishable(finishable)
            span.finishable = finishable
            span
          end

          def in_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
            span = start_span(name, attributes: attributes, links: links, start_timestamp: start_timestamp, kind: kind)
            begin
              yield
            rescue => e
              NewRelic::Agent.notice_error(e)
              raise
            end
          ensure
            span&.finish
          end

          private

          def get_span_from_finishable(finishable)
            case finishable
            when NewRelic::Agent::Transaction
              finishable.segments.first.instance_variable_get(:@otel_span)
            when NewRelic::Agent::Transaction::Segment
              finishable.instance_variable_get(:@otel_span)
            else
              NewRelic::Agent.logger.warn('Tracer#get_span_from_finishable failed to get span from finishable - finishable is not a transaction or segment')
              nil
            end
          end

          def can_start_transaction?(parent_span_context)
            parent_span_context.remote? || !parent_span_context.valid?
          end

          def internal_span_kind_with_invalid_parent?(kind, parent_span_context)
            !parent_span_context.valid? && kind == :internal
          end

          def add_remote_partent_span_context_to_txn(txn, parent_span_context)
            return unless txn.is_a?(NewRelic::Agent::Transaction) && parent_span_context.remote?

            txn.trace_id = parent_span_context.trace_id
            txn.parent_span_id = parent_span_context.span_id
          end
        end
      end
    end
  end
end
