# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module TracePatch
        def current_span(context = nil)
          return super if context

          storage = otel_current_storage
          return super if storage[:nr_otel_recursion_guard]

          nr_span = storage[:nr_otel_current_span]
          return nr_span if nr_span

          # Fallback with recursion protection
          storage[:nr_otel_recursion_guard] = true
          result = super
          storage[:nr_otel_recursion_guard] = nil

          result
        rescue => e
          NewRelic::Agent.logger.debug("Error in OpenTelemetry.current_span override, falling back to original implementation: #{e}")
          super
        end

        private

        def otel_current_storage
          if NewRelic::Agent.config[:dispatcher] == :falcon
            Fiber.current
          else
            Thread.current
          end
        end
      end
    end
  end
end
