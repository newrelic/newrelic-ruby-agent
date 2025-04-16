# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Opentelemetry
      # TODO: should you be a singleton? should you be a module? do we need an instance? can we just call a setup method or something?
      def initialize
        puts 'Opentelemetry initialize'
        # TODO: Update the definition checks - add a check for config
        return unless defined?(OpenTelemetry)# && NewRelic::Agent.config[:'feature_flag.otel_instrumentation']

        run_requires

        # TODO: Turn off New Relic instrumentation
        ::OpenTelemetry.tracer_provider = NewRelic::Agent::OpenTelemetry::Trace::TracerProvider.new
      end

      def run_requires
        require 'opentelemetry' # requires the opentelemetry-api gem
        require_relative 'opentelemetry/trace'
      end
    end
  end
end
