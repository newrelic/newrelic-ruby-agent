# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class OpenTelemetryHandler
      # TODO: should you be a singleton? should you be a module? do we need an instance? can we just call a setup method or something?
      def initialize
        # no-op without OpenTelemetry API & config
        return unless defined?(OpenTelemetry) && NewRelic::Agent.config[:'feature_flag.opentelemetry_bridge']

        OpenTelemetryHandler.install_bridge
      end

      private

      def self.install_bridge
        require 'opentelemetry' # requires the opentelemetry-api gem
        require_relative 'opentelemetry/trace'

        # TODO: Turn off New Relic instrumentation
        ::OpenTelemetry.tracer_provider = NewRelic::Agent::OpenTelemetry::Trace::TracerProvider.new
      end
    end
  end
end
