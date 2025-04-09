# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class TracerProvider
        def initialize
          @span_processors = []
        end
        # do we need a registration mechanism like in the main SDK?
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
