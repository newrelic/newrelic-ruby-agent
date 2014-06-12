# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/method_tracer'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction_state'
require 'new_relic/agent/instrumentation/queue_time'
require 'new_relic/agent/instrumentation/controller_instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      class MiddlewareProxy
        include ::NewRelic::Agent::MethodTracer

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

        def self.needs_wrapping?(target)
          (
            !target.respond_to?(:_nr_has_middleware_tracing) &&
            !is_sinatra_app?(target)
          )
        end

        def self.wrap(target, is_app=false)
          if needs_wrapping?(target)
            self.new(target, is_app)
          else
            target
          end
        end

        def initialize(target, is_app=false)
          @target            = target
          @is_app            = is_app
          @category          = determine_category
          @target_class_name = determine_class_name
          @transaction_name  = "#{determine_prefix}#{@target_class_name}/call"
          @transaction_opts  = {
            :transaction_name => @transaction_name
          }
        end

        def determine_category
          if @is_app
            :rack
          else
            :middleware
          end
        end

        def determine_prefix
          ::NewRelic::Agent::Instrumentation::ControllerInstrumentation::TransactionNamer.prefix_for_category(nil, @category)
        end

        # In 'normal' usage, the target will be an application instance that
        # responds to #call. With Rails, however, the target may be a subclass
        # of Rails::Application that defines a method_missing that proxies #call
        # to a singleton instance of the the subclass. We need to ensure that we
        # capture the correct name in both cases.
        def determine_class_name
          if @target.is_a?(Class)
            @target.name
          else
            @target.class.name
          end
        end

        def _nr_has_middleware_tracing
          true
        end

        def transaction_options(env)
          if env[CAPTURED_REQUEST_KEY]
            @transaction_opts
          else
            env[CAPTURED_REQUEST_KEY] = true
            queue_timefrontend_timestamp = QueueTime.parse_frontend_timestamp(env)
            @transaction_opts.merge(
              :request          => ::Rack::Request.new(env),
              :apdex_start_time => queue_timefrontend_timestamp
            )
          end
        end

        def call(env)
          opts = transaction_options(env)
          state = NewRelic::Agent::TransactionState.tl_get

          begin
            txn = Transaction.start(state, @category, opts)
            @target.call(env)
          rescue => e
            txn.notice_error(e)
            raise
          ensure
            Transaction.stop(state)
          end
        end

        def target_for_testing
          @target
        end
      end
    end
  end
end
