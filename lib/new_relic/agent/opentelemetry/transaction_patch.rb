# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module TransactionPatch
        attr_accessor :opentelemetry_context

        def initialize(_category, _options)
          @opentelemetry_context = {}
          super
        end

        def set_current_segment(new_segment)
          @current_segment_lock.synchronize do
            unless opentelemetry_context.empty?
              ::OpenTelemetry::Context.detach(opentelemetry_context[otel_current_span_key])
            end

            span = find_or_create_span(new_segment)
            ctx = ::OpenTelemetry::Context.current.set_value(otel_current_span_key, span)
            token = ::OpenTelemetry::Context.attach(ctx)

            opentelemetry_context[otel_current_span_key] = token
          end

          super
        end

        def remove_current_segment_by_thread_id(id)
          # make sure the context is fully detached when the transaction ends
          @current_segment_lock.synchronize do
            ::OpenTelemetry::Context.detach(opentelemetry_context[otel_current_span_key])
            opentelemetry_context.delete(id)
          end

          super
        end

        private

        def find_or_create_span(segment)
          if segment.instance_variable_defined?(:@otel_span)
            segment.instance_variable_get(:@otel_span)
          else
            span = Trace::Span.new(span_context: span_context_from_segment(segment))
            segment.instance_variable_set(:@otel_span, span)
            span
          end
        end

        def span_context_from_segment(segment)
          ::OpenTelemetry::Trace::SpanContext.new(
            trace_id: segment.transaction.trace_id,
            span_id: segment.guid,
            trace_flags: ::OpenTelemetry::Trace::TraceFlags::SAMPLED,
            remote: false
          )
        end

        def otel_current_span_key
          # CURRENT_SPAN_KEY is a private constant
          ::OpenTelemetry::Trace.const_get(:CURRENT_SPAN_KEY)
        end
      end
    end
  end
end
