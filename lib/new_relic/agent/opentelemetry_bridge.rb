# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class OpenTelemetryBridge
      # Exclude tracers by default to prevent double-reporting.
      # Affects libraries that the Ruby agent already instruments automatically.
      # Can be overridden via the opentelemetry.traces.include configuration.
      # https://opentelemetry.io/ecosystem/registry/?language=ruby&flag=native
      DEFAULT_EXCLUDED_TRACERS = %w[
        elasticsearch-api
        dalli
        OpenTelemetry::Instrumentation::ActionMailer
        OpenTelemetry::Instrumentation::ActionPack
        OpenTelemetry::Instrumentation::ActionView
        OpenTelemetry::Instrumentation::ActiveJob
        OpenTelemetry::Instrumentation::ActiveRecord
        OpenTelemetry::Instrumentation::ActiveStorage
        OpenTelemetry::Instrumentation::ActiveSupport
        OpenTelemetry::Instrumentation::AwsLambda
        OpenTelemetry::Instrumentation::AwsSdk
        OpenTelemetry::Instrumentation::Bunny
        OpenTelemetry::Instrumentation::ConcurrentRuby
        OpenTelemetry::Instrumentation::Dalli
        OpenTelemetry::Instrumentation::Ethon
        OpenTelemetry::Instrumentation::Excon
        OpenTelemetry::Instrumentation::Grape
        OpenTelemetry::Instrumentation::GraphQL
        OpenTelemetry::Instrumentation::Grpc
        OpenTelemetry::Instrumentation::HTTP
        OpenTelemetry::Instrumentation::HttpClient
        OpenTelemetry::Instrumentation::HTTPX
        OpenTelemetry::Instrumentation::Logger
        OpenTelemetry::Instrumentation::Mongo
        OpenTelemetry::Instrumentation::NetHTTP
        OpenTelemetry::Instrumentation::Rack
        OpenTelemetry::Instrumentation::Rails
        OpenTelemetry::Instrumentation::Rake
        OpenTelemetry::Instrumentation::Rdkafka
        OpenTelemetry::Instrumentation::Redis
        OpenTelemetry::Instrumentation::Resque
        OpenTelemetry::Instrumentation::RubyKafka
        OpenTelemetry::Instrumentation::Sidekiq
        OpenTelemetry::Instrumentation::Sinatra
      ].freeze

      def initialize(events)
        # currently, we only have support for traces
        # this method should change when we add support for metrics and logs.
        if defined?(OpenTelemetry) && Agent.config[:'opentelemetry.enabled'] && Agent.config[:'opentelemetry.traces.enabled']
          OpenTelemetryBridge.install
          events.subscribe(:initial_configuration_complete) do
            NewRelic::Agent.record_metric('Supportability/Tracing/Ruby/OpenTelemetryBridge/enabled', 0.0)
          end
        else
          events.subscribe(:initial_configuration_complete) do
            NewRelic::Agent.record_metric('Supportability/Tracing/Ruby/OpenTelemetryBridge/disabled', 0.0)
          end
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
