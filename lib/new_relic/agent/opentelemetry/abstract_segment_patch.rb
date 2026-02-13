# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module AbstractSegmentPatch
        def force_finish
          if instance_variable_defined?(:@otel_span)
            otel_span = instance_variable_get(:@otel_span)
            if otel_span.respond_to?(:finish) && !otel_span.instance_variable_get(:@finished)
              begin
                otel_span.finish

                return if finished?
              rescue => e
                NewRelic::Agent.logger.debug("Error finishing OpenTelemetry span during force_finish: #{e}")
              end
            end
          end

          super
        end
      end
    end
  end
end
