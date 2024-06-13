# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

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

    class MiddlewareOne < SimpleMiddleware; end

    class MiddlewareTwo < SimpleMiddleware; end

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
        use(MiddlewareOne)
        use(MiddlewareTwo)

        map('/prefix1') do
          run(PrefixAppOne.new)
        end

        map('/prefix2') do
          use(MiddlewareThree)
          run(PrefixAppTwo.new)
        end

        run(ExampleApp.new)
      end
    end

    def test_metrics_for_mapped_prefix
      get('/prefix1')

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
        'Supportability/API/drop_buffered_data',
        ['Middleware/Rack/BuilderMapTest::MiddlewareOne/call', 'Controller/Rack/BuilderMapTest::PrefixAppOne/call'],
        ['Middleware/Rack/BuilderMapTest::MiddlewareTwo/call', 'Controller/Rack/BuilderMapTest::PrefixAppOne/call'],
        ['Nested/Controller/Rack/BuilderMapTest::PrefixAppOne/call', 'Controller/Rack/BuilderMapTest::PrefixAppOne/call']
      ])
    end

    def test_metrics_for_mapped_prefix_with_extra_middleware
      get('/prefix2')

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
        'Supportability/API/drop_buffered_data',
        ['Middleware/Rack/BuilderMapTest::MiddlewareOne/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call'],
        ['Middleware/Rack/BuilderMapTest::MiddlewareTwo/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call'],
        ['Middleware/Rack/BuilderMapTest::MiddlewareThree/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call'],
        ['Nested/Controller/Rack/BuilderMapTest::PrefixAppTwo/call', 'Controller/Rack/BuilderMapTest::PrefixAppTwo/call']
      ])
    end
  end

end
