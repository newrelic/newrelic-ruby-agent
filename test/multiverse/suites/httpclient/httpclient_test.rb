# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "httpclient"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class HTTPClientTest < Test::Unit::TestCase
  include HttpClientTestCases

  def client_name
    "HTTPClient"
  end

  def get_response(url=nil)
    HTTPClient.get(url || default_url)
  end

  def head_response
    HTTPClient.head(default_url)
  end

  def post_response
    HTTPClient.post(default_url, :body => "")
  end

  def request_instance
    httpclient_req = HTTP::Message.new_request(:get, 'http://newrelic.com')
    NewRelic::Agent::HTTPClients::HTTPClientHTTPRequest.new(httpclient_req)
  end

  def response_instance(headers = {})
    httpclient_resp = HTTP::Message.new_response('')
    headers.each do |k, v|
      httpclient_resp.http_header[k] = v
    end
    NewRelic::Agent::HTTPClients::HTTPClientHTTPResponse.new(httpclient_resp)
  end
end
