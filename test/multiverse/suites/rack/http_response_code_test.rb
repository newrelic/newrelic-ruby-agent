# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

  require File.join(File.dirname(__FILE__), 'example_app')
  require 'new_relic/rack/browser_monitoring'
  require 'new_relic/rack/agent_hooks'

  class HttpResponseCodeTest < Minitest::Test
    include MultiverseHelpers

    setup_and_teardown_agent

    include Rack::Test::Methods

    def app
      Rack::Builder.app do
        use ResponseCodeMiddleware
        use NewRelic::Rack::AgentHooks
        run ExampleApp.new
      end
    end

    def test_records_http_response_code_on_analytics_events
      rsp = get '/', {'override-response-code' => 404}
      assert_equal(404, rsp.status)
      assert_equal(404, get_last_analytics_event[2][:'http.statusCode'])

      rsp = get '/', {'override-response-code' => 302}
      assert_equal(302, rsp.status)
      assert_equal(302, get_last_analytics_event[2][:'http.statusCode'])
    end

    def test_skips_http_response_code_if_middleware_tracing_disabled
      with_config(:disable_middleware_instrumentation => true) do
        rsp = get '/', {'override-response-code' => 404}
        assert_equal(404, rsp.status)
        refute get_last_analytics_event[2][:'http.statusCode']

        rsp = get '/', {'override-response-code' => 302}
        assert_equal(302, rsp.status)
        refute get_last_analytics_event[2][:'http.statusCode']
      end
    end
  end

end
