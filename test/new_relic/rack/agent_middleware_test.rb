# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'
require 'new_relic/rack/agent_middleware'
require 'new_relic/agent/tracer'

module NewRelic
  module Rack
    class AgentMiddlewareTest < Minitest::Test
      class ExampleMiddleware < AgentMiddleware
        def traced_call(env)
          @app.call(env)
        end
      end

      attr_reader :middleware, :env

      def setup
        NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)

        @app = lambda { |env| [200, {}, ['yeah!']] }
        @middleware = ExampleMiddleware.new(@app)
        @env = {}
      end

      def test_with_tracing_creates_a_transaction
        middleware.call(env)
        assert_metrics_recorded('Controller/Middleware/Rack/NewRelic::Rack::AgentMiddlewareTest::ExampleMiddleware/call')
      end
    end
  end
end
