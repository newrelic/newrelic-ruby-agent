# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_state'
require 'new_relic/agent/instrumentation/controller_instrumentation'

module NewRelic
  module Rack
    module AgentMiddleware
      include Agent::Instrumentation::ControllerInstrumentation

      DEFAULT_TRACE_OPTIONS = { :category => :middleware, :name => "call".freeze }.freeze

      def _nr_has_middleware_tracing
        true
      end

      def call(env)
        if env[:newrelic_captured_request]
          opts = DEFAULT_TRACE_OPTIONS
        else
          opts = DEFAULT_TRACE_OPTIONS.merge(:request => ::Rack::Request.new(env))
          env[:newrelic_captured_request] = true
        end

        perform_action_with_newrelic_trace(opts) do
          traced_call(env)
        end
      end
    end
  end
end
