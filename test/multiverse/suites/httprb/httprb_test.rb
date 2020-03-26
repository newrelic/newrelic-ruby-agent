# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "http"
require "newrelic_rpm"
require "http_client_test_cases"

class HTTPTest < Minitest::Test
  include HttpClientTestCases

  def client_name
    "http.rb"
  end

  def is_unsupported_1x?
    defined?(::HTTP::VERSION) && HTTP::VERSION < '1.0.0'
  end

  def get_response(url=nil, headers=nil)
    HTTP.get(url || default_url, :headers => headers)
  end

  def get_wrapped_response url
    NewRelic::Agent::HTTPClients::HTTPResponse.new get_response url
  end

  def head_response
    HTTP.head(default_url)
  end

  def post_response
    HTTP.post(default_url, :body => "")
  end

  def put_response
    HTTP.put(default_url, :body => "")
  end

  def delete_response
    HTTP.delete(default_url, :body => "")
  end

  # NOTE, some versions of HTTPrb gem implements body with
  # String.new("").force_encoding(@encoding) which won't work 
  # with Ruby 2.7 and it's automatic freezing of string literals.
  def body(res)
    res.body.to_s
  end

  def request_instance
    options = {
      verb: :get,
      uri: 'http://newrelic.com'
    }

    httprb_req =
      if is_unsupported_1x?
        HTTP::Request.new(*options.values)
      else
        HTTP::Request.new(options)
      end

    ::NewRelic::Agent::HTTPClients::HTTPRequest.new(httprb_req)
  end

  def response_instance(headers = {})
    options = {
      status: 200,
      version: '1.1',
      headers: headers,
      body: ''
    }

    httprb_resp = is_unsupported_1x? ? HTTP::Response.new(*options.values) : HTTP::Response.new(options)

    NewRelic::Agent::HTTPClients::HTTPResponse.new(httprb_resp)
  end

  def timeout_error_class
    HTTP::TimeoutError
  end

  def simulate_error_response
    HTTP::Connection.any_instance.stubs(:send_proxy_connect_request).raises(timeout_error_class.new)
    get_response
  end

end
