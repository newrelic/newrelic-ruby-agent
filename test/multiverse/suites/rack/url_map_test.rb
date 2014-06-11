# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'multiverse_helpers'

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

class UrlMapTest < Minitest::Test
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
        'HttpDispatcher',
        'Middleware/all',
        'Controller/Rack/UrlMapTest::ExampleApp/call',
        'Apdex/Rack/UrlMapTest::ExampleApp/call',
        'Middleware/Rack/UrlMapTest::MiddlewareOne/call',
        'Middleware/Rack/UrlMapTest::MiddlewareTwo/call',
        'Nested/Controller/Rack/UrlMapTest::ExampleApp/call',
        ['Middleware/Rack/UrlMapTest::MiddlewareOne/call', 'Controller/Rack/UrlMapTest::ExampleApp/call'],
        ['Middleware/Rack/UrlMapTest::MiddlewareTwo/call', 'Controller/Rack/UrlMapTest::ExampleApp/call'],
        ['Nested/Controller/Rack/UrlMapTest::ExampleApp/call', 'Controller/Rack/UrlMapTest::ExampleApp/call']
      ])
    end
  end

  def test_metrics_for_mapped_prefix
    get '/prefix1'

    assert_metrics_recorded_exclusive([
      'Apdex',
      'HttpDispatcher',
      'Middleware/all',
      'Controller/Rack/UrlMapTest::PrefixAppOne/call',
      'Apdex/Rack/UrlMapTest::PrefixAppOne/call',
      'Middleware/Rack/UrlMapTest::MiddlewareOne/call',
      'Middleware/Rack/UrlMapTest::MiddlewareTwo/call',
      'Nested/Controller/Rack/UrlMapTest::PrefixAppOne/call',
      ['Middleware/Rack/UrlMapTest::MiddlewareOne/call', 'Controller/Rack/UrlMapTest::PrefixAppOne/call'],
      ['Middleware/Rack/UrlMapTest::MiddlewareTwo/call', 'Controller/Rack/UrlMapTest::PrefixAppOne/call'],
      ['Nested/Controller/Rack/UrlMapTest::PrefixAppOne/call', 'Controller/Rack/UrlMapTest::PrefixAppOne/call']
    ])
  end

  def test_metrics_for_mapped_prefix_with_extra_middleware
    get '/prefix2'

    assert_metrics_recorded_exclusive([
      'Apdex',
      'HttpDispatcher',
      'Middleware/all',
      'Controller/Rack/UrlMapTest::PrefixAppTwo/call',
      'Apdex/Rack/UrlMapTest::PrefixAppTwo/call',
      'Middleware/Rack/UrlMapTest::MiddlewareOne/call',
      'Middleware/Rack/UrlMapTest::MiddlewareTwo/call',
      'Middleware/Rack/UrlMapTest::MiddlewareThree/call',
      'Nested/Controller/Rack/UrlMapTest::PrefixAppTwo/call',
      ['Middleware/Rack/UrlMapTest::MiddlewareOne/call', 'Controller/Rack/UrlMapTest::PrefixAppTwo/call'],
      ['Middleware/Rack/UrlMapTest::MiddlewareTwo/call', 'Controller/Rack/UrlMapTest::PrefixAppTwo/call'],
      ['Middleware/Rack/UrlMapTest::MiddlewareThree/call', 'Controller/Rack/UrlMapTest::PrefixAppTwo/call'],
      ['Nested/Controller/Rack/UrlMapTest::PrefixAppTwo/call', 'Controller/Rack/UrlMapTest::PrefixAppTwo/call']
    ])
  end
end

end
