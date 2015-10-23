# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

require File.join(File.dirname(__FILE__), 'example_app')
require 'new_relic/rack/browser_monitoring'
require 'new_relic/rack/agent_hooks'
require 'new_relic/rack/error_collector'

class RackCascadeTest < Minitest::Test
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
      run Rack::Cascade.new([FirstCascadeExampleApp.new, SecondCascadeExampleApp.new])
    end
  end

  def test_insert_js_does_not_fire_for_rack_cascade_404_responses
    rsp = get '/', { 'body' => '<html><head></head><body></body></html>', 'override-response-code' => 404 }
    refute(rsp.body.include?('script'), "\nExpected\n---\n#{rsp.body}\n---\nnot to include 'script'.")
  end

  def test_rack_cascade_transactions_are_named_for_the_last_app
    rsp = get '/cascade'
    assert_metrics_recorded('Controller/SecondCascadeExampleApp/call')
  end
end
end
