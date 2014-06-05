# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_state'
require 'new_relic/agent/instrumentation/controller_instrumentation'
require 'new_relic/agent/instrumentation/middleware_proxy'

module NewRelic
  module Rack
    module AgentMiddleware
      include Agent::Instrumentation::ControllerInstrumentation

      DEFAULT_TRACE_OPTIONS = { :category => :middleware, :name => "call".freeze }.freeze

      def _nr_has_middleware_tracing
        true
      end

      def call(env)
        if env[NewRelic::Agent::Instrumentation::MiddlewareProxy::CAPTURED_REQUEST_KEY]
          opts = DEFAULT_TRACE_OPTIONS
        else
          opts = DEFAULT_TRACE_OPTIONS.merge(:request => ::Rack::Request.new(env))
          env[NewRelic::Agent::Instrumentation::MiddlewareProxy::CAPTURED_REQUEST_KEY] = true
        end

        perform_action_with_newrelic_trace(opts) do
          traced_call(env)
        end
      end

      # Overriding these methods inherited from ControllerInstrumentation is
      # a performance optimization. See the comment in MiddlewareProxy for
      # details.
      def ignore_apdex?;   false; end
      def ignore_enduser?; false; end
      def do_not_trace?;   false; end
    end
  end
end
