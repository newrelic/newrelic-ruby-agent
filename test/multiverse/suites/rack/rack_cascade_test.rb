# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), 'example_app')
require 'new_relic/rack/browser_monitoring'
require 'new_relic/rack/agent_hooks'
require 'new_relic/rack/error_collector'

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

  class HttpResponseCodeTest < Minitest::Test
    include MultiverseHelpers

    setup_and_teardown_agent(
      :beacon                 => 'beacon',
      :browser_key            => 'browserKey',
      :js_agent_loader        => 'loader',
      :application_id         => '5',
      :'rum.enabled'          => true,
      :license_key            => 'a' * 40
    )

    include Rack::Test::Methods

    def app
      Rack::Builder.app do
        use NewRelic::Rack::AgentHooks
        use NewRelic::Rack::BrowserMonitoring
        use ResponseCodeMiddleware
        run ExampleApp.new
      end
    end

    def test_insert_js_does_not_fire_for_rack_cascade_404_responses
      rsp = get '/', { 'body' => '<html><head></head><body></body></html>', 'override-response-code' => 404 }
      refute(rsp.body.include?('script'), "\nExpected\n---\n#{rsp.body}\n---\nnot to include 'script'.")
    end

  end
end
