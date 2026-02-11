# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'tasks/newrelic'

module Custom
  # Custom::Helpers - class designed to demonstrate manually added transaction and method tracers
  class Helpers
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    include ::NewRelic::Agent::MethodTracer

    def self.custom_class_method
      APP_TRACER.in_span('custom_class_method', kind: :consumer) do
        'Hello from a class method!'.reverse.split.shuffle.map(&:upcase).join
        custom_class_method_too
      end
    end

    def self.custom_class_method_too
      span = APP_TRACER.start_span('Custom/CLMtesting/ClassMethod', kind: :internal)
      'Hello from a second class method!'[3, 16].split.select { |s| s.include?('o') }
      span&.finish
    end

    class << self
      include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
      include ::NewRelic::Agent::MethodTracer
      add_transaction_tracer :custom_class_method, category: :task if !NewRelic::Agent.config[:'opentelemetry.enabled']
      add_method_tracer :custom_class_method_too, %w[Custom/CLMtesting/ClassMethod] if !NewRelic::Agent.config[:'opentelemetry.enabled']
    end

    def custom_instance_method
      APP_TRACER.in_span('custom_instance_method', kind: :consumer) do
        2 => x
        custom_instance_method_too
      end
    end
    add_transaction_tracer :custom_instance_method, category: :task if !NewRelic::Agent.config[:'opentelemetry.enabled']

    def custom_instance_method_too
      span = APP_TRACER.start_span('Custom/CLMtesting/InstanceMethod', kind: :internal)
      # This raised an error, not sure if it was on purpose
      2 | 1 == 3
      span&.finish
    end
    add_method_tracer :custom_instance_method_too, %w[Custom/CLMtesting/InstanceMethod] if !NewRelic::Agent.config[:'opentelemetry.enabled']
  end
end
