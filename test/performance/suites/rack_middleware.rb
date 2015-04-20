# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'

class RackMiddleware < Performance::TestCase
  class TestMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end

  # We want 10 middlewares each with different names so that we end up with
  # different metric names for each one. This is more realistic than using the
  # same name 10 times.
  class TestMiddlewareA < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareB < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareC < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareD < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareE < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareF < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareG < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareH < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareI < TestMiddleware; def call(e); @app.call(e); end; end
  class TestMiddlewareJ < TestMiddleware; def call(e); @app.call(e); end; end

  class TestAppWithParams
    def call(env)
      params = {
        'user' => {
          'shipping_address' => {
            'street' => '1234 Nowhere Road',
            'city'   => 'Nowhere',
            'state'  => 'TX'
          },
          'billing_address' => {
            'street' => '4321 Nowhere Lane',
            'city'   => 'Nowhere',
            'state'  => 'TX'
          }
        }
      }
      perform_action_with_newrelic_trace(:name => 'dorkbot', :params => params) do
        [200, { 'Content-Type' => 'text/html' }, ['<body>hi</body>']]
      end
    end
  end

  class TestApp
    def call(env)
      [200, { 'Content-Type' => 'text/html' }, ['<body>hi</body>']]
    end
  end

  def setup
    require 'new_relic/rack/browser_monitoring'

    @config = {
      :beacon          => 'beacon',
      :browser_key     => 'browserKey',
      :js_agent_loader => 'loader',
      :encoding_key    => 'lolz',
      :application_id  => '5, 6', # collector can return app multiple ids
      :'rum.enabled'   => true,
      :license_key     => 'a' * 40,
      :developer_mode  => false
    }
    NewRelic::Agent.config.add_config_for_testing(@config)

    NewRelic::Agent.manual_start(
      :developer_mode => false,
      :monitor_mode   => false
    )

    NewRelic::Agent.agent.events.notify(:finished_configuring)

    middlewares = [
      TestMiddlewareA,
      TestMiddlewareB,
      TestMiddlewareC,
      TestMiddlewareD,
      TestMiddlewareE,
      TestMiddlewareF,
      TestMiddlewareG,
      TestMiddlewareH,
      TestMiddlewareI,
      TestMiddlewareJ,
      NewRelic::Rack::BrowserMonitoring
    ]

    TestAppWithParams.class_eval do
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    end

    @stack = Rack::Builder.new do
      middlewares.each { |m| use m }
      run TestApp.new
    end.to_app

    @stack_with_params = Rack::Builder.new do
      middlewares.each { |m| use m }
      run TestAppWithParams.new
    end.to_app

    @env = {
      'SCRIPT_NAME'  => '',
      'PATH_INFO'    => '/users/12/blogs',
      'QUERY_STRING' => 'q=foobar'
    }
  end

  def test_basic_middleware_stack()
    measure do
      @stack.call(@env.dup)
    end
  end

  def test_request_with_params_capture_params_off
    measure do
      @stack_with_params.call(@env.dup)
    end
  end

  def test_request_with_params_capture_params_on
    NewRelic::Agent.config.add_config_for_testing(:capture_params => true)
    NewRelic::Agent.agent.events.notify(:finished_configuring)
    measure do
      @stack_with_params.call(@env.dup)
    end
  end
end
