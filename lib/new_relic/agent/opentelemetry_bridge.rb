# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class OpenTelemetryBridge
      def initialize
        # no-op without OpenTelemetry API & config
        return unless defined?(OpenTelemetry) &&
          NewRelic::Agent.config[:'opentelemetry_bridge.enabled']

        OpenTelemetryBridge.install
      end

      private

      def self.install
        require 'opentelemetry' # requires the opentelemetry-api gem
        require_relative 'opentelemetry/trace'
        require_relative 'opentelemetry/transaction_patch'
        require_relative 'opentelemetry/context'

        # TODO: Add a warning if SDK gem is installed

        ::OpenTelemetry.tracer_provider = OpenTelemetry::Trace::TracerProvider.new
        Transaction.prepend(OpenTelemetry::TransactionPatch)
        ::OpenTelemetry.propagation = OpenTelemetry::Context::Propagation::TracePropagator.new
      end
    end
  end
end
