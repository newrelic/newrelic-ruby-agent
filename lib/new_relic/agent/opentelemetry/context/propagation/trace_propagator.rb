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

            # TODO: determine if we need to create our own versions of the setter and getter
            def inject(carrier, context: ::OpenTelemetry::Context.current, setter: ::OpenTelemetry::Context::Propagation.text_map_setter)
              NewRelic::Agent::DistributedTracing.insert_distributed_trace_headers(carrier)
            end

            def extract(carrier, context: ::OpenTelemetry::Context.current, getter: ::OpenTelemetry::Context::Propagation.text_map_getter)
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
