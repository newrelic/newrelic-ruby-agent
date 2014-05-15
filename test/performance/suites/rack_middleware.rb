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

  class TestApp
    def call(env)
      [200, {}, ['hi']]
    end
  end

  def setup
    NewRelic::Agent.manual_start(
      :developer_mode => false,
      :monitor_mode   => false
    )
    @stack = Rack::Builder.new do
      use TestMiddlewareA
      use TestMiddlewareB
      use TestMiddlewareC
      use TestMiddlewareD
      use TestMiddlewareE
      use TestMiddlewareF
      use TestMiddlewareG
      use TestMiddlewareH
      use TestMiddlewareI
      use TestMiddlewareJ
      run TestApp.new
    end.to_app
    @env = {}
  end

  def test_basic_middleware_stack()
    iterations.times do
      @stack.call(@env.dup)
    end
  end
end
