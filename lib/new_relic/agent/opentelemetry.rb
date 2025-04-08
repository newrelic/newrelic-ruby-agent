# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Opentelemetry
      # should you be a singleton? should you be a module? do we need an instance? can we just call a setup method or something?
      def initialize
        puts 'Opentelemetry initialize'
        return unless defined?(OpenTelemetry)
        # return unless NewRelic::Agent.config[:'feature_flag.otel_instrumentation'] &&

        run_requires

        # do I have to turn off New Relic instrumentation?

        ::OpenTelemetry.tracer_provider = NewRelic::Agent::OpenTelemetry::TracerProvider.new
        processor = NewRelic::Agent::OpenTelemetry::SpanProcessor.new # doesn't need an exporter because we'll give it one?
        ::OpenTelemetry.tracer_provider.add_span_processor(processor)
      end

      def run_requires
        require 'opentelemetry' # requires the OpenTelemetry API
        require_relative 'opentelemetry/tracer_provider'
        require_relative 'opentelemetry/tracer'
        require_relative 'opentelemetry/span_processor'
        require_relative 'opentelemetry/span'
      end

      # def depends_on
      #   # needs the config flag
      #   # needs the api
      #   # DOES NOT NEED the sdk (we are the SDK)
      #   # TODO: consider min versions
      #   NewRelic::Agent.config[:'feature_flag.otel_instrumentation'] &&
      #     defined?(OpenTelemetry)
      # end

      # def execute
      #   # normally a resource is passed, should we make one?
      #   OpenTelemetry.tracer_provider = NewRelic::Agent::OpenTelemetry::TracerProvider.new
      #   processor = NewRelic::Agent::OpenTelemetry::SpanProcessor.new # doesn't need an exporter because we'll give it one?
      #   OpenTelemetry.tracer_provider.add_span_processor = processor
      # end
    end
  end
end



# # Create a LoggerProvider
# logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new
# # Create a batching processor configured to export to the OTLP exporter
# processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new)
# # Add the processor to the LoggerProvider
# logger_provider.add_log_record_processor(processor)
# # Access a Logger for your library from your LoggerProvider
# logger = logger_provider.logger(name: 'my_app_or_gem', version: '0.1.0')

# logger_provider.shutdown

