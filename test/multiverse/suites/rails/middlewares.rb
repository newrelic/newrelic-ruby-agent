# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Middlewares (potentially) for use from both Rails 2 and Rails 3+ tests

class ErrorMiddleware
  def initialize(app, options={})
    @app = app
  end

  def call(env)
    path = ::Rack::Request.new(env).path_info
    raise "middleware error" if path.match(/\/middleware_error\/before/)
    result = @app.call(env)
    raise "middleware error" if path.match(/\/middleware_error\/after/)
    result
  end
end
