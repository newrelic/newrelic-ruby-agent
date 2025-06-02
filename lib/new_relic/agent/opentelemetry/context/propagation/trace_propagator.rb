# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0
module NewRelic
  module Agent
    module OpenTelemetry
      module Context
        module Propagation
          class TracePropagator
            EMPTY_LIST = [].freeze
            private_constant(:EMPTY_LIST)

            # The setter argument is a no-op, added for consistency with the OpenTelemetry API
            def inject(carrier, context: ::OpenTelemetry::Context.current, setter: nil)
              NewRelic::Agent::DistributedTracing.insert_distributed_trace_headers(carrier)
            end

            # The getter argument is a no-op, added for consistency with the OpenTelemetry API
            def extract(carrier, context: ::OpenTelemetry::Context.current, getter: nil)
              NewRelic::Agent::DistributedTracing.accept_distributed_trace_headers
            end

            def fields
              EMPTY_LIST
            end
          end
        end
      end
    end
  end
end
