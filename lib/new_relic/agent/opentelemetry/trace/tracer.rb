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
            # have the option of starting a transaction if the parent is remote or the span context is invalid/empty
            if parent_span_context.remote? || !parent_span_context.valid?
              # internal spans without a parent context should not start transactions
              # but internal spans with a remote parent should start transactions
              return if !parent_span_context.valid? && kind == :internal

              finishable = NewRelic::Agent::Tracer.start_transaction_or_segment(name: name, category: :otel)

              if finishable.is_a?(NewRelic::Agent::Transaction)
                finishable.trace_id = parent_span_context.trace_id
                finishable.parent_span_id = parent_span_context.span_id
              end
            else
              finishable = NewRelic::Agent::Tracer.start_segment(name: name)
            end

            span = ::OpenTelemetry::Trace.current_span
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
        end
      end
    end
  end
end
