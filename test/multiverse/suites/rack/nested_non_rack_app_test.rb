# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), 'example_app')

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

class NestedNonRackAppTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  include Rack::Test::Methods

  class ExampleMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end

  class RailsishApp
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def call(env)
      perform_action_with_newrelic_trace(:category => :controller, :name => 'inner') do
        [200, {}, ['hey']]
      end
    end
  end

  def app
    Rack::Builder.app do
      use ExampleMiddleware
      run RailsishApp.new
    end
  end

  def test_outermost_middleware_contributes_to_middleware_all_if_txn_name_is_non_rack
    get '/'

    assert_metrics_recorded_exclusive(
      [
        "Apdex",
        "ApdexAll",
        "Apdex/NestedNonRackAppTest::RailsishApp/inner",
        "Controller/NestedNonRackAppTest::RailsishApp/inner",
        "HttpDispatcher",
        "Middleware/all",
        "Middleware/Rack/NestedNonRackAppTest::ExampleMiddleware/call",
        ["Middleware/Rack/NestedNonRackAppTest::ExampleMiddleware/call", "Controller/NestedNonRackAppTest::RailsishApp/inner"],
        "Nested/Controller/NestedNonRackAppTest::RailsishApp/inner",
        ["Nested/Controller/NestedNonRackAppTest::RailsishApp/inner", "Controller/NestedNonRackAppTest::RailsishApp/inner"],
        "Nested/Controller/Rack/NestedNonRackAppTest::RailsishApp/call",
        ["Nested/Controller/Rack/NestedNonRackAppTest::RailsishApp/call", "Controller/NestedNonRackAppTest::RailsishApp/inner"]
      ],
      :ignore_filter => /^Supportability/
    )
  end
end

end
