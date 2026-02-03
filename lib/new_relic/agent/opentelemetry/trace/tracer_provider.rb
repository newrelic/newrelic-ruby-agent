# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class TracerProvider < ::OpenTelemetry::Trace::TracerProvider
          Key = Struct.new(:name, :version)
          private_constant(:Key)

          def initialize
            @registry = {}
            @registry_mutex = Mutex.new
          end

          def excluded_tracers
            @excluded ||= (NewRelic::Agent.config[:'opentelemetry.traces.exclude'].split(',') -
              NewRelic::Agent.config[:'opentelemetry.traces.include'].split(',')
                          )
          end

          def tracer(name = nil, version = nil)
            # We create a no-op tracer if the tracer is configured to be excluded
            # This should only be run when a custom tracer that isn't defined by
            # OpenTelemetry instrumentation is excluded
            return ::OpenTelemetry::Trace::Tracer.new if excluded_tracers.include?(name)

            NewRelic::Agent.logger.warn 'OpenTelemetry::Trace::TracerProvider#tracer called without providing a tracer name.' if name.nil? || name.empty?
            @registry_mutex.synchronize { @registry[Key.new(name, version)] ||= OpenTelemetry::Trace::Tracer.new(name, version) }
          end
        end
      end
    end
  end
end
