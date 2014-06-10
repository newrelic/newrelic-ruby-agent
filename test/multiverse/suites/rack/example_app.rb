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
    advance_time(1)
    status, headers, body = @app.call(env)
    headers['MiddlewareOne'] = '1'

    advance_time(1)
    [status, headers, body]
  end
end

class MiddlewareTwo
  def initialize(app, tag, &blk)
    @app = app
    @tag = tag
    @block = blk
  end

  def call(env)
    advance_time(1)
    request = Rack::Request.new(env)

    if request.params['return-early']
      status, headers, body = '200', {}, ['Hi']
    else
      status, headers, body = @app.call(env)
    end

    headers['MiddlewareTwo'] = '2'
    headers['MiddlewareTwoTag'] = @tag

    @block.call(headers)

    [status, headers, body]
  end
end
