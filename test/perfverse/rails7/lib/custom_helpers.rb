# frozen_string_literal: true

require 'tasks/newrelic'

module Custom
  # Custom::Helpers - class designed to demonstrate manually added transaction and method tracers
  class Helpers
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    include ::NewRelic::Agent::MethodTracer

    def self.custom_class_method
      'Hello from a class method!'.reverse.split.shuffle.map(&:upcase).join
      custom_class_method_too
    end

    def self.custom_class_method_too
      'Hello from a second class method!'[3, 16].split.select { |s| s.include?('o') }
    end

    class << self
      include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
      include ::NewRelic::Agent::MethodTracer
      add_transaction_tracer :custom_class_method, category: :task
      add_method_tracer :custom_class_method_too, %w[Custom/CLMtesting/ClassMethod]
    end

    def custom_instance_method
      2 => x
      custom_instance_method_too
    end
    add_transaction_tracer :custom_instance_method, category: :task

    def custom_instance_method_too
      2 | 1 =~ 3
    end
    add_method_tracer :custom_instance_method_too, %w[Custom/CLMtesting/InstanceMethod]
  end
end
