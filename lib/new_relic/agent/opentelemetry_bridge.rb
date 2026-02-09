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
        OpenTelemetry::Instrumentation::ActionMailer::Instrumentation
        OpenTelemetry::Instrumentation::ActionPack::Instrumentation
        OpenTelemetry::Instrumentation::ActionView::Instrumentation
        OpenTelemetry::Instrumentation::ActiveJob::Instrumentation
        OpenTelemetry::Instrumentation::ActiveRecord::Instrumentation
        OpenTelemetry::Instrumentation::ActiveStorage::Instrumentation
        OpenTelemetry::Instrumentation::ActiveSupport::Instrumentation
        OpenTelemetry::Instrumentation::AwsLambda::Instrumentation
        OpenTelemetry::Instrumentation::AwsSdk::Instrumentation
        OpenTelemetry::Instrumentation::Bunny::Instrumentation
        OpenTelemetry::Instrumentation::ConcurrentRuby::Instrumentation
        OpenTelemetry::Instrumentation::Dalli::Instrumentation
        OpenTelemetry::Instrumentation::Ethon::Instrumentation
        OpenTelemetry::Instrumentation::Excon::Instrumentation
        OpenTelemetry::Instrumentation::Grape::Instrumentation
        OpenTelemetry::Instrumentation::GraphQL::Instrumentation
        OpenTelemetry::Instrumentation::Grpc::Instrumentation
        OpenTelemetry::Instrumentation::HTTP::Instrumentation
        OpenTelemetry::Instrumentation::HttpClient::Instrumentation
        OpenTelemetry::Instrumentation::HTTPX::Instrumentation
        OpenTelemetry::Instrumentation::Logger::Instrumentation
        OpenTelemetry::Instrumentation::Mongo::Instrumentation
        OpenTelemetry::Instrumentation::Net::HTTP::Instrumentation
        OpenTelemetry::Instrumentation::Rack::Instrumentation
        OpenTelemetry::Instrumentation::Rails::Instrumentation
        OpenTelemetry::Instrumentation::Rake::Instrumentation
        OpenTelemetry::Instrumentation::Rdkafka::Instrumentation
        OpenTelemetry::Instrumentation::Redis::Instrumentation
        OpenTelemetry::Instrumentation::Resque::Instrumentation
        OpenTelemetry::Instrumentation::RubyKafka::Instrumentation
        OpenTelemetry::Instrumentation::Sidekiq::Instrumentation
        OpenTelemetry::Instrumentation::Sinatra::Instrumentation
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
        binding.irb
        ::OpenTelemetry::Instrumentation.registry.install_all
      end
    end
  end
end
