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

            # TODO: Implement in full for inbound distributed tracing test
            # The getter argument is a no-op, added for consistency with the OpenTelemetry API
            def extract(carrier, context: ::OpenTelemetry::Context.current, getter: nil)
              NewRelic::Agent::DistributedTracing.accept_distributed_trace_headers
            end
          end
        end
      end
    end
  end
end
