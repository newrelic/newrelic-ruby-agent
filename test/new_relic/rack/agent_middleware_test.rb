# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/rack/agent_middleware'
require 'new_relic/agent/transaction_state'

module NewRelic
  module Rack
    class AgentMiddlewareTest < Minitest::Test
      class ExampleMiddleware
        include AgentMiddleware

        def traced_call(env)
          [200, {}, ['yeah!']]
        end
      end

      attr_reader :middleware, :env

      def setup
        @middleware = ExampleMiddleware.new
        @env = {}
      end

      def test_with_tracing_creates_a_transaction
        middleware.call(env)
        assert_metrics_recorded('Controller/Rack/NewRelic::Rack::AgentMiddlewareTest::ExampleMiddleware/call')
      end
    end
  end
end
