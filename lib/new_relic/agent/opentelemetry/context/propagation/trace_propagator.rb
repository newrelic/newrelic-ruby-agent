# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Context
        module Propagation
          class TracePropagator
            # The carrier is the object carrying the headers
            # The context argument is a no-op, as the OpenTelemetry context is not used
            # The setter argument is a no-op, added for consistency with the OpenTelemetry API
            def inject(carrier, context: ::OpenTelemetry::Context.current, setter: nil)
              # TODO: determine if we need to update this method to take Context into account
              NewRelic::Agent::DistributedTracing.insert_distributed_trace_headers(carrier)
            end

            def extract(carrier, context: ::OpenTelemetry::Context.current, getter: ::OpenTelemetry::Context::Propagation.text_map_getter)
              trace_parent_value = carrier[TRACEPARENT_KEY]
              return context unless trace_parent_value

              # There's an optional format key that we may need to address eventually
              # If the format is rack, then the key is HTTP_TRACEPARENT
              trace_context = NewRelic::Agent::DistributedTracing::TraceContext.parse(carrier: carrier)

              tp = trace_context.trace_parent

              # TODO: Add tracestate parsing
              span_context = ::OpenTelemetry::Trace::SpanContext.new(trace_id: tp['trace_id'], span_id: tp['parent_id'], trace_flags: tp['trace_flags'], tracestate: nil, remote: true)

              span = ::OpenTelemetry::Trace.non_recording_span(span_context)
              ::OpenTelemetry::Trace.context_with_span(span, parent_context: context)
            rescue StandardError => e
              NewRelic::Agent.logger.error("Unable to extract context: #{e.message}")
              context
            end
          end
        end
      end
    end
  end
end
