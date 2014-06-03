# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      class MiddlewareProxy
        include ::NewRelic::Agent::MethodTracer
        include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

        CALL = "call".freeze unless defined?(CALL)

        def self.is_sinatra_app?(target)
          defined?(::Sinatra::Base) && target.kind_of?(::Sinatra::Base)
        end

        def self.wrap(target, force_transaction=false)
          if target.respond_to?(:_nr_has_middleware_tracing)
            target
          elsif is_sinatra_app?(target)
            target
          else
            self.new(target, force_transaction)
          end
        end

        def initialize(target, force_transaction=false)
          @target            = target
          @force_transaction = force_transaction
          @target_class_name = target.class.name.freeze
          @metric_name       = "Nested/Controller/Rack/#{@target_class_name}/call".freeze
        end

        def _nr_has_middleware_tracing
          true
        end

        def call(env)
          if @force_transaction || !Transaction.current
            req = ::Rack::Request.new(env)
            perform_action_with_newrelic_trace(:category => :rack, :request => req, :name => CALL, :class_name => @target_class_name) do
              @target.call(env)
            end
          else
            trace_execution_scoped(@metric_name) do
              @target.call(env)
            end
          end
        end
      end
    end
  end
end
