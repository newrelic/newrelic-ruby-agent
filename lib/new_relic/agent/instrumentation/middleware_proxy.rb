# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      class MiddlewareProxy
        include ::NewRelic::Agent::MethodTracer
        include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

        CAPTURED_REQUEST_KEY = 'newrelic.captured_request'.freeze unless defined?(CAPTURED_REQUEST_KEY)
        CALL = "call".freeze unless defined?(CALL)

        # This class is used to wrap classes that are passed to
        # Rack::Builder#use without synchronously instantiating those classes.
        # A MiddlewareProxy::Generator responds to new, like a Class would, and
        # passes through arguments to new to the original target class.
        class Generator
          def initialize(middleware_class)
            @middleware_class = middleware_class
          end

          def new(*args, &blk)
            middleware_instance = @middleware_class.new(*args, &blk)
            MiddlewareProxy.wrap(middleware_instance)
          end
        end

        def self.is_sinatra_app?(target)
          defined?(::Sinatra::Base) && target.kind_of?(::Sinatra::Base)
        end

        def self.for_class(target_class)
          Generator.new(target_class)
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
          }.freeze
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
          if env[CAPTURED_REQUEST_KEY]
            opts = @trace_opts
          else
            opts = @trace_opts.merge(:request => ::Rack::Request.new(env))
            env[CAPTURED_REQUEST_KEY] = true
          end
          perform_action_with_newrelic_trace(opts) do
            @target.call(env)
          end
        end

        # These next three methods are defined in ControllerInstrumentation, and
        # we're overriding the definitions here as a performance optimization.
        #
        # The default implementation of each on ControllerInstrumentation calls
        # through to newrelic_read_attr with a String argument, then calls
        # instance_variable_get with a String derived from that String.
        #
        # These methods are present in order to support a declarative syntax for
        # ignoring specific transactions in the context of Rails or Sinatra apps
        # but in the context of Rack middleware, they don't even really make
        # sense, so we just hard-code a false return value for each.
        def ignore_apdex?;   false; end
        def ignore_enduser?; false; end
        def do_not_trace?;   false; end

        def target_for_testing
          @target
        end
      end
    end
  end
end
