# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), 'example_app')
require 'new_relic/rack/browser_monitoring'
require 'new_relic/rack/agent_hooks'
require 'new_relic/rack/error_collector'

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

class SmallestAppTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  include Rack::Test::Methods

  def app
    Rack::Builder.app do
      run ExampleApp.new
    end
  end

  def test_middlewares_not_instrumented_if_disabled_by_config
    with_config(:disable_middleware_instrumentation => true) do
      get '/'
    end
    assert_metrics_recorded_exclusive(
      [],
      :ignore_filter => /^Supportability\/EnvironmentReport/
    )
  end

  def test_middlewares_record_metrics
    get '/'
    assert_metrics_recorded_exclusive(
      [
        "Apdex",
        "HttpDispatcher",
        "Middleware/all",
        "Apdex/Rack/ExampleApp/call",
        "Controller/Rack/ExampleApp/call",
      ],
      :ignore_filter => /^Supportability\/EnvironmentReport/
    )
  end
end

end
