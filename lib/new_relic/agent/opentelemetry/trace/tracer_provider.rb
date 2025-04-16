# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        # TODO: Do we inherit from the OpenTelemetry API like the SDK does?
        class TracerProvider < ::OpenTelemetry::Trace::TracerProvider
          # TODO: Add a registration mechanism for tracers like exists in the SDK
          def tracer(name = nil, version = nil)
            @tracer ||= Tracer.new(name, version)
          end
        end
      end
    end
  end
end
