# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

require File.join(File.dirname(__FILE__), 'example_app')
require 'new_relic/rack/browser_monitoring'
require 'new_relic/rack/agent_hooks'
require 'new_relic/rack/error_collector'

class HttpResponseContentTypeTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  include Rack::Test::Methods

  def app
    Rack::Builder.app do
      use ResponseContentTypeMiddleware
      use NewRelic::Rack::AgentHooks
      run ExampleApp.new
    end
  end

  def test_records_response_content_type_on_analytics_events
    rsp = get '/', { 'override-content-type' => 'application/json' }
    assert_equal('application/json', rsp.headers['Content-Type'])
    assert_equal('application/json', get_last_analytics_event[2][:'response.headers.contentType'])

    rsp = get '/', { 'override-content-type' => 'application/xml' }
    assert_equal('application/xml', rsp.headers['Content-Type'])
    assert_equal('application/xml', get_last_analytics_event[2][:'response.headers.contentType'])
  end

  def test_skips_response_content_type_if_middleware_tracing_disabled
    with_config(:disable_middleware_instrumentation => true) do
      rsp = get '/', { 'override-content-type' => 'application/json' }
      assert_equal('application/json', rsp.headers['Content-Type'])
      assert_nil get_last_analytics_event[2][:'response.headers.contentType']

      rsp = get '/', { 'override-content-type' => 'application/xml' }
      assert_equal('application/xml', rsp.headers['Content-Type'])
      assert_nil get_last_analytics_event[2][:'response.headers.contentType']
    end
  end
end

end
