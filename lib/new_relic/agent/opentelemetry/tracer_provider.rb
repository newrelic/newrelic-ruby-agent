# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      # TODO: Do we inherit from the OpenTelemetry API like the SDK does?
      class TracerProvider # < ::OpenTelemetry::Trace::TracerProvider
        def initialize
          @span_processors = []
        end

        # TODO: do we need a registration mechanism like in the main SDK?
        # I think we do, because there could still be a lot of tracers and we need to access them rather than keep making them; check the API documentation
        def tracer(name = nil, version = nil)
          @tracer ||= Tracer.new(name, version)
        end


        def add_span_processor(span_processor)
          puts 'add_span_processor hit'
        end
      end
    end
  end
end
