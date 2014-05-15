# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class ExampleApp
  def call(env)
    ['200', {'Content-Type' => 'text/html', 'ExampleApp' => '0'}, ['A barebones rack app.']]
  end
end

class MiddlewareOne
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers['MiddlewareOne'] = '1'
    [status, headers, body]
  end
end

class MiddlewareTwo
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers['MiddlewareTwo'] = '2'
    [status, headers, body]
  end
end
