# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Opentelemetry
      # should you be a singleton? should you be a module? do we need an instance? can we just call a setup method or something?
      def initialize
        puts 'Opentelemetry initialize'
        # TODO: Update the definition checks - add a check for config
        return unless defined?(OpenTelemetry)
        # return unless NewRelic::Agent.config[:'feature_flag.otel_instrumentation'] &&

        run_requires

        # TODO: Turn off New Relic instrumentation?
        # TODO: Do we need an Exporter?
        ::OpenTelemetry.tracer_provider = NewRelic::Agent::OpenTelemetry::TracerProvider.new

        processor = NewRelic::Agent::OpenTelemetry::SpanProcessor.new

        ::OpenTelemetry.tracer_provider.add_span_processor(processor)
      end

      def run_requires
        require 'opentelemetry' # requires the OpenTelemetry API
        require_relative 'opentelemetry/tracer_provider'
        require_relative 'opentelemetry/tracer'
        require_relative 'opentelemetry/span_processor'
        require_relative 'opentelemetry/span'
      end
    end
  end
end
