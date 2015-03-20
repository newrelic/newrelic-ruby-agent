# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/http_clients/em_http_wrappers'

class EMHTTPResponseTest < Minitest::Test

  def test_get_nil_header
    assert_nil(wrapped_response[""])
  end

  def test_get_header_value
    key = "header_key"
    value = "header_value"
    @response = { key => value }
    assert_equal(wrapped_response[key], value)
  end

  def test_get_hash_headers
    @response = { "header_key" => "header_value" }
    assert_equal(wrapped_response.to_hash, @response)
  end

  def test_get_nil_hash_headers
    assert_equal(NewRelic::Agent::HTTPClients::EMHTTPResponse.new(nil).to_hash, {})
  end

  def wrapped_response
    NewRelic::Agent::HTTPClients::EMHTTPResponse.new(@response ||= {})
  end
end

class EMHTTPRequestTest < Minitest::Test

  def test_type
    assert_equal(wrapped_request.type, "EMHTTPRequest")
  end

  def test_host
    @host = "test.newrelic.rpm"
    assert_equal(wrapped_request.host, @host)
  end

  def test_default_method
    assert_equal(wrapped_request.method, "GET")
  end

  def test_method
    @method = "post"
    assert_equal(wrapped_request.method, @method.upcase)
  end

  def test_get_header
    key = "header_key"
    value = "header_value"
    @headers = { key => value }
    assert_equal(wrapped_request[key], value)
  end

  def test_set_header
    key = "header_key"
    value = "header_value"
    wrapped_request[key] = value
    assert_equal(wrapped_request[key], value)
  end

  def test_uri
    assert_equal(wrapped_request.uri, @uri)
  end

  def wrapped_request
    @uri = mock("uri")
    @uri.stubs(:host).returns(@host)

    # We want to test also HttpClientOptions from em-http-request,
    # but testing em-http-request is out of scope in this test, so use
    # HttpClientOptions with mocked methods instead of testing
    # HttpClientOptions itself.
    request = HttpClientOptions.new
    request.stubs(:uri).returns(@uri)
    request.stubs(:headers).returns(@headers ||= {})
    request.stubs(:method).returns(@method)

    NewRelic::Agent::HTTPClients::EMHTTPRequest.new(request)
  end
end
