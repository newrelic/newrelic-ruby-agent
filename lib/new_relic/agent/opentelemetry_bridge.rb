# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class OpenTelemetryBridge
      def initialize
        # currently, we only have support for traces
        # this method should change when we add support for metrics and logs.
        if defined?(OpenTelemetry) && Agent.config[:'opentelemetry.enabled'] && Agent.config[:'opentelemetry.traces.enabled']
          OpenTelemetryBridge.install
          NewRelic::Agent.record_metric('Supportability/Tracing/Ruby/OpenTelemetryBridge/enabled', 0.0)
          # else
          # This record metric calls happen before the agent is fully started, which causes us to log warnings every single time the agent runs.
          # NewRelic::Agent.record_metric('Supportability/Tracing/Ruby/OpenTelemetryBridge/disabled', 0.0)
        end
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
