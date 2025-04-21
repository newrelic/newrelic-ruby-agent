# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class OpenTelemetryHandler
      def initialize
        # no-op without OpenTelemetry API & config
        return unless defined?(OpenTelemetry) &&
          NewRelic::Agent.config[:'opentelemetry_bridge.enabled']

        OpenTelemetryHandler.install_bridge
      end

      private

      def self.install_bridge
        require 'opentelemetry' # requires the opentelemetry-api gem
        require_relative 'opentelemetry/trace'

        ::OpenTelemetry.tracer_provider = NewRelic::Agent::OpenTelemetry::Trace::TracerProvider.new
      end
    end
  end
end
