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
            # detach the current token, if one is present
            unless opentelemetry_context.empty?
              ::OpenTelemetry::Context.detach(opentelemetry_context[otel_current_span_key])
            end

            span = nil

            # create an otel span for the new segment
            if new_segment.instance_variable_defined?(:@otel_span)
              span = new_segment.instance_variable_get(:@otel_span)
            else
              span = Trace::Span.new(span_context: span_context_from_segment(new_segment))
              new_segment.instance_variable_set(:@otel_span, span)
            end

            # set otel's current span to the newly created otel span
            ctx = ::OpenTelemetry::Context.current.set_value(otel_current_span_key, span)

            # attach the token generated from updating the current span
            token = ::OpenTelemetry::Context.attach(ctx)

            # update our context tracking hash to correlate the context token
            # with the otel_current_span_key
            opentelemetry_context[otel_current_span_key] = token
          end

          super
        end

        def span_context_from_segment(segment)
          ::OpenTelemetry::Trace::SpanContext.new(
            trace_id: segment.transaction.trace_id,
            span_id: segment.guid,
            trace_flags: ::OpenTelemetry::Trace::TraceFlags::SAMPLED,
            remote: false
          )
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

        def otel_current_span_key
          # CURRENT_SPAN_KEY is a private constant
          ::OpenTelemetry::Trace.const_get(:CURRENT_SPAN_KEY)
        end
      end
    end
  end
end
