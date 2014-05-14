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
      10.times do
        use TestMiddleware
      end
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
