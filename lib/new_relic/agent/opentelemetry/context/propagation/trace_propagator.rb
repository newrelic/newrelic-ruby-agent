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

            # The return value for this method should be an instance of the
            # OpenTelemetry Context class. The return value of
            # #accept_distributed_trace_headers is a transaction, so we cannot
            # use it to extract the context.
            def extract(carrier, context: ::OpenTelemetry::Context.current, getter: ::OpenTelemetry::Context::Propagation.text_map_getter)
              carrier_format = determine_format(getter)
              trace_context = NewRelic::Agent::DistributedTracing::TraceContext.parse(
                carrier: carrier,
                format: carrier_format,
                trace_state_entry_key: Transaction::TraceContext::AccountHelpers.trace_state_entry_key
              )

              return context if trace_context.nil?

              tp = trace_context.trace_parent
              span_context = ::OpenTelemetry::Trace::SpanContext.new(
                trace_id: tp['trace_id'],
                span_id: tp['parent_id'],
                trace_flags: tp['trace_flags'],
                tracestate: trace_context.trace_state_payload,
                remote: true
              )
              span = ::OpenTelemetry::Trace.non_recording_span(span_context)

              ::OpenTelemetry::Trace.context_with_span(span, parent_context: context)
            rescue StandardError => e
              NewRelic::Agent.logger.error("Unable to extract context: #{e.message}")
              context
            end

            private

            # The getter is the way OpenTelemetry handles Rack vs. non-Rack
            # formats. Rather than using their parser, get the class info we
            # need to do things the New Relic way
            def determine_format(getter)
              case getter
              when ::OpenTelemetry::Context::Propagation::RackEnvGetter
                FORMAT_RACK
              when defined?(::OpenTelemetry::Common) && ::OpenTelemetry::Common::Propagation::RackEnvGetter
                FORMAT_RACK
              else
                FORMAT_NON_RACK
              end
            end
          end
        end
      end
    end
  end
end
