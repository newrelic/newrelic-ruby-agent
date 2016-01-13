# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if NewRelic::Agent::Instrumentation::RackHelpers.puma_rack_version_supported?

class PumaRackBuilderTest < Minitest::Test
  include MultiverseHelpers

  class ExampleApp
    def call env
      [200, {'Content-Type' => 'text/html'}, ['Hello!']]
    end
  end

  class MiddlewareOne
    def initialize app
      @app = app
    end

    def call env
      env['MiddlewareOne'] = true
      @app.call env
    end
  end

  class MiddlewareTwo
    def initialize app
      @app = app
    end

    def call env
      env['MiddlewareTwo'] = true
      @app.call env
    end
  end

  def setup
    @app = build_app
    @env = {}
  end

  def teardown
    NewRelic::Agent.drop_buffered_data
  end

  def build_app
    Puma::Rack::Builder.app do
      use MiddlewareOne
      use MiddlewareTwo
      run ExampleApp.new
    end
  end


  def test_middlewares_are_visited_with_puma_rack
    @app.call @env
    assert @env['MiddlewareOne'], 'Expected MiddlewareOne to be present and true in env'
    assert @env['MiddlewareTwo'], 'Expected MiddlewareTwo to be present and true in env'
  end

  def test_puma_rack_builder_is_auto_instrumented
    @app.call @env

    assert_metrics_recorded_exclusive(
      [
        "Apdex",
        "ApdexAll",
        "HttpDispatcher",
        "Middleware/all",
        "Apdex/Rack/PumaRackBuilderTest::ExampleApp/call",
        "Controller/Rack/PumaRackBuilderTest::ExampleApp/call",
        "Middleware/Rack/PumaRackBuilderTest::MiddlewareOne/call",
        "Middleware/Rack/PumaRackBuilderTest::MiddlewareTwo/call",
        "Nested/Controller/Rack/PumaRackBuilderTest::ExampleApp/call",
        ["Middleware/Rack/PumaRackBuilderTest::MiddlewareOne/call", "Controller/Rack/PumaRackBuilderTest::ExampleApp/call"],
        ["Middleware/Rack/PumaRackBuilderTest::MiddlewareTwo/call", "Controller/Rack/PumaRackBuilderTest::ExampleApp/call"],
        ["Nested/Controller/Rack/PumaRackBuilderTest::ExampleApp/call", "Controller/Rack/PumaRackBuilderTest::ExampleApp/call"]
      ],
      :ignore_filter => /^Supportability/
    )
  end
end
end
