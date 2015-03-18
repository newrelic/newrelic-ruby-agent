# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# These tests confirm functionality when using the Rack::Builder class. In
# particular, combinations of map, use and run should result in the right
# metrics. In internals changed across Rack versions, so it's important to
# check as our middleware and Rack instrumentation has grown.

require 'multiverse_helpers'

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

class BuilderMapTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  include Rack::Test::Methods

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
  class MiddlewareThree < SimpleMiddleware; end

  class ExampleApp
    def call(env)
      [200, {}, [self.class.name]]
    end
  end

  class PrefixAppOne < ExampleApp; end
  class PrefixAppTwo < ExampleApp; end

  def app
    Rack::Builder.app do
      use MiddlewareOne
      use MiddlewareTwo

      map '/prefix1' do
        run PrefixAppOne.new
      end

      map '/prefix2' do
        use MiddlewareThree
        run PrefixAppTwo.new
      end

      # Rack versions prior to 1.4 did not support combining map and run at the
      # top-level in the same Rack::Builder.
      if Rack::VERSION[1] >= 4
        run ExampleApp.new
      end
    end
  end

  if Rack::VERSION[1] >= 4
    def test_metrics_for_default_prefix
      get '/'

      assert_metrics_recorded_exclusive([
        'Apdex',
        'ApdexAll',
        'HttpDispatcher',
        'Middleware/all',
        'Controller/Rack/BuilderMapTest::ExampleApp/call',
        'Apdex/Rack/BuilderMapTest::ExampleApp/call',
        'Middleware/Rack/BuilderMapTest::MiddlewareOne/call',
        'Middleware/Rack/BuilderMapTest::MiddlewareTwo/call',
        'Nested/Controller/Rack/BuilderMapTest::ExampleApp/call',
        ['Middleware/Rack/BuilderMapTest::MiddlewareOne/call', 'Controller/Rack/BuilderMapTest::ExampleApp/call'],
        ['Middleware/Rack/BuilderMapTest::MiddlewareTwo/call', 'Controller/Rack/BuilderMapTest::ExampleApp/call'],
        ['Nested/Controller/Rack/BuilderMapTest::ExampleApp/call', 'Controller/Rack/BuilderMapTest::ExampleApp/call']
      ])
    end
  end

  def test_metrics_for_mapped_prefix
    get '/prefix1'

    assert_metrics_recorded([
      'Apdex',
      'ApdexAll',
      'HttpDispatcher',
      'Middleware/all',
      'Controller/Rack/BuilderMapTest::PrefixAppOne/call',
      'Apdex/Rack/BuilderMapTest::PrefixAppOne/call',
      'Middleware/Rack/BuilderMapTest::MiddlewareOne/call',
      'Middleware/Rack/BuilderMapTest::MiddlewareTwo/call',
      'Nested/Controller/Rack/BuilderMapTest::PrefixAppOne/call',
      ['Middleware/Rack/BuilderMapTest::MiddlewareOne/call', 'Controller/Rack/BuilderMapTest::PrefixAppOne/call'],
      ['Middleware/Rack/BuilderMapTest::MiddlewareTwo/call', 'Controller/Rack/BuilderMapTest::PrefixAppOne/call'],
      ['Nested/Controller/Rack/BuilderMapTest::PrefixAppOne/call', 'Controller/Rack/BuilderMapTest::PrefixAppOne/call']
    ])
  end

  def test_metrics_for_mapped_prefix_with_extra_middleware
    get '/prefix2'

    assert_metrics_recorded([
      'Apdex',
      'ApdexAll',
      'HttpDispatcher',
      'Middleware/all',
      'Controller/Rack/BuilderMapTest::PrefixAppTwo/call',
      'Apdex/Rack/BuilderMapTest::PrefixAppTwo/call',
      'Middleware/Rack/BuilderMapTest::MiddlewareOne/call',
      'Middleware/Rack/BuilderMapTest::MiddlewareTwo/call',
      'Middleware/Rack/BuilderMapTest::MiddlewareThree/call',
      'Nested/Controller/Rack/BuilderMapTest::PrefixAppTwo/call',
      ['Middleware/Rack/BuilderMapTest::MiddlewareOne/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call'],
      ['Middleware/Rack/BuilderMapTest::MiddlewareTwo/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call'],
      ['Middleware/Rack/BuilderMapTest::MiddlewareThree/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call'],
      ['Nested/Controller/Rack/BuilderMapTest::PrefixAppTwo/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call']
    ])
  end
end

end
