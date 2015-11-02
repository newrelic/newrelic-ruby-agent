# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# These tests are for confirming that our direct support Rack::URLMap works
# properly. Tests against the builder interface more commonly used (i.e. map)
# can be found elsewhere in this suite.

if NewRelic::Agent::Instrumentation::RackHelpers.version_supported?

class UrlMapTest < Minitest::Test
  include MultiverseHelpers

  def teardown
    NewRelic::Agent.drop_buffered_data
  end

  class SimpleMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end

  class MiddlewareOne   < SimpleMiddleware; end
  class MiddlewareTwo   < SimpleMiddleware; end

  class ExampleApp
    def call(env)
      [200, {}, [self.class.name]]
    end
  end

  class PrefixAppOne < ExampleApp; end
  class PrefixAppTwo < ExampleApp; end

  def app
    defined?(Puma) ? puma_rack_app : rack_app
  end

  def rack_app
    Rack::Builder.app do
      use MiddlewareOne
      use MiddlewareTwo

      run Rack::URLMap.new(
        '/prefix1' => PrefixAppOne.new,
        '/prefix2' => PrefixAppTwo.new)
    end
  end

  def puma_rack_app
    Puma::Rack::Builder.app do
      use MiddlewareOne
      use MiddlewareTwo

      run Puma::Rack::URLMap.new(
        '/prefix1' => PrefixAppOne.new,
        '/prefix2' => PrefixAppTwo.new)
    end
  end

  if defined?(Rack) && Rack::VERSION[1] >= 4
    def test_metrics_for_default_prefix
      get '/'

      assert_metrics_recorded_exclusive([
        'Apdex',
        'ApdexAll',
        'HttpDispatcher',
        'Middleware/all',
        'Controller/Rack/UrlMapTest::ExampleApp/call',
        'Apdex/Rack/UrlMapTest::ExampleApp/call',
        'Middleware/Rack/UrlMapTest::MiddlewareOne/call',
        'Middleware/Rack/UrlMapTest::MiddlewareTwo/call',
        nested_controller_metric,
        'Nested/Controller/Rack/UrlMapTest::ExampleApp/call',
        ['Middleware/Rack/UrlMapTest::MiddlewareOne/call', 'Controller/Rack/UrlMapTest::ExampleApp/call'],
        ['Middleware/Rack/UrlMapTest::MiddlewareTwo/call', 'Controller/Rack/UrlMapTest::ExampleApp/call'],
        ['Nested/Controller/Rack/UrlMapTest::ExampleApp/call', 'Controller/Rack/UrlMapTest::ExampleApp/call'],
        [nested_controller_metric, 'Controller/Rack/UrlMapTest::ExampleApp/call']
      ])
    end
  end

  def test_metrics_for_mapped_prefix
    get '/prefix1'

    assert_metrics_recorded_exclusive([
      'Apdex',
      'ApdexAll',
      'HttpDispatcher',
      'Middleware/all',
      'Controller/Rack/UrlMapTest::PrefixAppOne/call',
      'Apdex/Rack/UrlMapTest::PrefixAppOne/call',
      'Middleware/Rack/UrlMapTest::MiddlewareOne/call',
      'Middleware/Rack/UrlMapTest::MiddlewareTwo/call',
      nested_controller_metric,
      'Nested/Controller/Rack/UrlMapTest::PrefixAppOne/call',
      ['Middleware/Rack/UrlMapTest::MiddlewareOne/call', 'Controller/Rack/UrlMapTest::PrefixAppOne/call'],
      ['Middleware/Rack/UrlMapTest::MiddlewareTwo/call', 'Controller/Rack/UrlMapTest::PrefixAppOne/call'],
      [nested_controller_metric, 'Controller/Rack/UrlMapTest::PrefixAppOne/call'],
      ['Nested/Controller/Rack/UrlMapTest::PrefixAppOne/call', 'Controller/Rack/UrlMapTest::PrefixAppOne/call']
    ])
  end

  def test_metrics_for_mapped_prefix_with_extra_middleware
    get '/prefix2'

    assert_metrics_recorded_exclusive([
      'Apdex',
      'ApdexAll',
      'HttpDispatcher',
      'Middleware/all',
      'Controller/Rack/UrlMapTest::PrefixAppTwo/call',
      'Apdex/Rack/UrlMapTest::PrefixAppTwo/call',
      'Middleware/Rack/UrlMapTest::MiddlewareOne/call',
      'Middleware/Rack/UrlMapTest::MiddlewareTwo/call',
      nested_controller_metric,
      'Nested/Controller/Rack/UrlMapTest::PrefixAppTwo/call',
      ['Middleware/Rack/UrlMapTest::MiddlewareOne/call', 'Controller/Rack/UrlMapTest::PrefixAppTwo/call'],
      ['Middleware/Rack/UrlMapTest::MiddlewareTwo/call', 'Controller/Rack/UrlMapTest::PrefixAppTwo/call'],
      [nested_controller_metric, 'Controller/Rack/UrlMapTest::PrefixAppTwo/call'],
      ['Nested/Controller/Rack/UrlMapTest::PrefixAppTwo/call', 'Controller/Rack/UrlMapTest::PrefixAppTwo/call']
    ])
  end

  def nested_controller_metric
    url_map_class = defined?(Puma) ? Puma::Rack::URLMap : Rack::URLMap
    "Nested/Controller/Rack/#{url_map_class}/call"
  end

  # We're not using Rack::Test so that we can test against an enviroment
  # that requires puma only. Since we're only using the `get` method this is
  # easy enough replicate. If this becomes a problem in the future perhaps we
  # revisit how we verify that
  def get path
    env = {
      "REQUEST_METHOD"=>"GET",
      "PATH_INFO"=>path,
      "SCRIPT_NAME"=>""
    }

    app.call env
  end
end

end
