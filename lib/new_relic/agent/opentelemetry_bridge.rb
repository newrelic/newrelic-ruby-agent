# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class OpenTelemetryBridge
      DEFAULT_EXCLUDED_TRACERS = %w[elasticsearch-api dalli].freeze

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
        install_instrumentation
      end

      def self.calculate_excluded_tracers
        excluded_names = NewRelic::Agent.config[:'opentelemetry.traces.exclude'].split(',').map(&:strip)
        included_names = NewRelic::Agent.config[:'opentelemetry.traces.include'].split(',').map(&:strip)

        # Priority order (highest to lowest):
        # 1. Configured exclude list - always excluded
        # 2. Configured include list - overrides default exclude
        # 3. Default exclude list - excluded unless overridden by configured include
        excluded_names + (DEFAULT_EXCLUDED_TRACERS - included_names)
      end

      def self.install_instrumentation
        return unless defined?(::OpenTelemetry::Instrumentation::Registry)

        excluded_set = calculate_excluded_tracers.to_set

        return ::OpenTelemetry::Instrumentation.registry.install_all if excluded_set.empty?

        registry = ::OpenTelemetry::Instrumentation.registry
        registry_lock = registry.instance_variable_get(:@lock)

        registry_lock.synchronize do
          instrumentation = registry.instance_variable_get(:@instrumentation)

          # Filter directly on objects, not strings
          without_excluded = instrumentation.reject do |inst|
            excluded_set.include?(inst.to_s)
          end

          registry.instance_variable_set(:@instrumentation, without_excluded)
        end

        ::OpenTelemetry::Instrumentation.registry.install_all
      end
    end
  end
end
