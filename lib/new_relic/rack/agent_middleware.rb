# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_state'
require 'new_relic/agent/instrumentation/controller_instrumentation'

module NewRelic
  module Rack
    module AgentMiddleware
      include Agent::Instrumentation::ControllerInstrumentation

      RESET_KEY = "newrelic.transaction_reset".freeze

      def _nr_has_middleware_tracing
        true
      end

      def call(env)
        req = ::Rack::Request.new(env)
        perform_action_with_newrelic_trace(:category => :middleware, :request => req, :name => "call") do
          traced_call(env)
        end
      end
    end
  end
end
