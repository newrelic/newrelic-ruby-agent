# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module RackMiddleware
        def self.already_instrumented?(middleware)
          middleware.instance_variable_get(:@_nr_traced_flag)
        end

        def self.mark_instrumented(middleware)
          middleware.instance_variable_set(:@_nr_traced_flag, true)
        end

        def self.add_new_relic_tracing_to_middleware(middleware)
          return if already_instrumented?(middleware)
          mark_instrumented(middleware)

          class << middleware
            include ::NewRelic::Agent::MethodTracer
            add_method_tracer(:call, "Nested/Controller/Rack/#{self.superclass.name}/call")
          end
        end

        def self.add_new_relic_transaction_tracing_to_middleware(middleware)
          return if already_instrumented?(middleware)
          mark_instrumented(middleware)

          class << middleware
            include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

            def call_with_new_relic_transaction_trace(env)
              req = ::Rack::Request.new(env)
              perform_action_with_newrelic_trace(:category => :rack, :request => req, :name => "call") do
                call_without_new_relic_transaction_trace(env)
              end
            end

            alias call_without_new_relic_transaction_trace call
            alias call call_with_new_relic_transaction_trace
          end
        end
      end
    end
  end
end
