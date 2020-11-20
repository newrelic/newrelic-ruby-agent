# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require "net/http"
require "newrelic_rpm"
require "http_client_test_cases"

module NetHttpTestCases  
  include HttpClientTestCases

  #
  # Support for shared test cases
  #

  def client_name
    "Net::HTTP"
  end

  def timeout_error_class
    Net::ReadTimeout
  end

  def simulate_error_response
    Net::HTTP.any_instance.stubs(:transport_request).raises(timeout_error_class.new)
    get_response
  end

  def get_response(url=nil, headers={})
    uri = default_uri
    uri = URI.parse(url) unless url.nil?
    path = uri.path.empty? ? '/' : uri.path

    start(uri) { |http| http.get(path, headers) }
  end

  def get_wrapped_response url
    NewRelic::Agent::HTTPClients::NetHTTPResponse.new get_response url
  end

  def get_response_multi(url, n)
    uri = URI(url)
    responses = []

    start(uri) do |conn|
      n.times do
        req = Net::HTTP::Get.new(url)
        responses << conn.request(req)
      end
    end

    responses
  end

  def head_response
    start(default_uri) { |http| http.head(default_uri.path) }
  end

  def post_response
    start(default_uri) { |http| http.post(default_uri.path, "") }
  end

  def put_response
    start(default_uri) { |http| http.put(default_uri.path, "") }
  end

  def delete_response
    start(default_uri) { |http| http.delete(default_uri.path) }
  end

  def create_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    if use_ssl?
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    http
  end

  def start(uri, &block)
    http = create_http(uri)
    http.start(&block)
  end

  def request_instance
    http = Net::HTTP.new(default_uri.host, default_uri.port)
    request = Net::HTTP::Get.new(default_uri.request_uri)
    NewRelic::Agent::HTTPClients::NetHTTPRequest.new(http, request)
  end

  def response_instance(headers = {})
    response = Net::HTTPResponse.new(nil, nil, nil)
    headers.each do |k,v|
      response[k] = v
    end
    NewRelic::Agent::HTTPClients::NetHTTPResponse.new response
  end

  #
  # Net::HTTP specific tests
  #
  def test_get__simple
    # Don't check this specific condition against SSL, since API doesn't support it
    return if use_ssl?

    in_transaction do
      Net::HTTP.get default_uri
    end

    assert_metrics_recorded([
      'External/all',
      'External/localhost/Net::HTTP/GET',
      'External/allOther',
      'External/localhost/all'
    ])
  end

  # https://newrelic.atlassian.net/browse/RUBY-835
  def test_direct_get_request_doesnt_double_count
    http = create_http(default_uri)
    in_transaction do
      http.request(Net::HTTP::Get.new(default_uri.request_uri))
    end

    assert_metrics_recorded(
      'External/localhost/Net::HTTP/GET' => { :call_count => 1 })
  end
end
