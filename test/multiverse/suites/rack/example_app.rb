# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class ExampleApp
  def call(env)
    req = Rack::Request.new(env)
    body = req.params['body'] || 'A barebones rack app.'

    status = '404' unless req.path == '/'
    [status || '200', {'Content-Type' => 'text/html', 'ExampleApp' => '0'}, [body]]
  end
end

class FirstCascadeExampleApp
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  def call(env)
    req = Rack::Request.new(env)
    body = req.params['body'] || 'A barebones rack cascade app.'

    status = '404' unless req.path == '/'
    [status || '200', {'Content-Type' => 'text/html', 'FirstCascadeExampleApp' => '0'}, [body]]
  end
  add_transaction_tracer :call
end

class SecondCascadeExampleApp
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  def call(env)
    req = Rack::Request.new(env)
    body = req.params['body'] || 'A barebones rack cascade app.'

    status = '404' unless req.path == '/'
    [status || '200', {'Content-Type' => 'text/html', 'SecondCascadeExampleApp' => '0'}, [body]]
  end
  add_transaction_tracer :call
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

class ResponseCodeMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    req = Rack::Request.new(env)

    result = @app.call(env)

    if req.params['override-response-code']
      response_code = req.params['override-response-code'].to_i
    else
      response_code = result[0]
    end

    [response_code, result[1], result[2]]
  end
end

class ResponseContentTypeMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    req = Rack::Request.new(env)

    status, headers, body = @app.call(env)

    if req.params['override-content-type']
      content_type = req.params['override-content-type']
      headers.update("Content-Type" => content_type)
    end

    [status, headers, body]
  end
end
