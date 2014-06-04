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

        def self.wrap(target, is_app=false)
          if target.respond_to?(:_nr_has_middleware_tracing)
            target
          elsif is_sinatra_app?(target)
            target
          else
            self.new(target, is_app)
          end
        end

        def initialize(target, is_app=false)
          @target            = target
          @is_app            = is_app
          @target_class_name = target.class.name.freeze
          @category          = determine_category
          @trace_opts        = {
            :name       => CALL,
            :category   => @category,
            :class_name => @target_class_name
          }
        end

        def determine_category
          if @is_app
            :rack
          else
            :middleware
          end
        end

        def _nr_has_middleware_tracing
          true
        end

        def call(env)
          @trace_opts[:request] = ::Rack::Request.new(env)
          perform_action_with_newrelic_trace(@trace_opts) do
            @target.call(env)
          end
        end
      end
    end
  end
end
