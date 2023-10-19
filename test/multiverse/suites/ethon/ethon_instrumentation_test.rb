# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'ethon'
require 'newrelic_rpm'
require 'http_client_test_cases'
require_relative '../../../../lib/new_relic/agent/http_clients/ethon_wrappers'
require_relative '../../../test_helper'

class EthonInstrumentationTest < Minitest::Test
  include HttpClientTestCases

  # Ethon::Easy#perform doesn't return a response object. Our Ethon
  # instrumentation knows that and works fine. But the shared HTTP
  # client test cases expect one, so we'll fake one.
  DummyResponse = Struct.new(:body, :response_headers)

  def test_ethon_multi
    easies = []
    count = 2
    in_transaction do
      multi = Ethon::Multi.new
      count.times do
        easy = Ethon::Easy.new
        easy.http_request(default_url, :get, {})
        easies << easy
        multi.add(easy)
      end
      multi.perform
    end

    multi_node_name = NewRelic::Agent::Instrumentation::Ethon::Multi::MULTI_SEGMENT_NAME
    node = find_node_with_name(last_transaction_trace, multi_node_name)

    assert node, "Unable to locate a node named '#{multi_node_name}'"
    assert_equal count, node.children.size,
      "Expected '#{multi_node_name}' node to have #{count} children, found #{node.children.size}"
    node.children.each { |child| assert_equal 'External/localhost/Ethon/GET', child.metric_name }
    easies.each do |easy|
      assert_match(/<html><head>/, easy.response_body)
      assert_match(%r{^HTTP/1.1 200 OK}, easy.response_headers)
    end
  end

  def test_host_is_host_from_uri
    skip_unless_minitest5_or_above

    host = 'silverpumpin.com'
    easy = Ethon::Easy.new(url: host)
    wrapped = NewRelic::Agent::HTTPClients::EthonHTTPRequest.new(easy)

    assert_equal host, wrapped.host
  end

  def test_host_is_default_host
    skip_unless_minitest5_or_above

    url = 'foxs'
    mock_uri = Minitest::Mock.new
    mock_uri.expect :host, nil, []
    URI.stub :parse, mock_uri, [url] do
      easy = Ethon::Easy.new(url: url)
      wrapped = NewRelic::Agent::HTTPClients::EthonHTTPRequest.new(easy)

      assert_equal NewRelic::Agent::HTTPClients::EthonHTTPRequest::DEFAULT_HOST, wrapped.host
    end
  end

  private

  def perform_easy_request(url, action, headers = nil)
    e = Ethon::Easy.new
    e.http_request(url, action, {})
    e.headers = headers if headers
    e.perform
    DummyResponse.new(e.response_body, e.response_headers)
  end

  # HttpClientTestCases required method
  def client_name
    NewRelic::Agent::HTTPClients::EthonHTTPRequest::ETHON
  end

  # HttpClientTestCases required method
  def get_response(url = default_url, headers = nil)
    perform_easy_request(url, :get, headers)
  end

  # HttpClientTestCases required method
  def post_response
    perform_easy_request(default_url, :post)
  end

  # HttpClientTestCases required method
  # NOTE that the request won't actually be performed; simply inspected
  def request_instance
    NewRelic::Agent::HTTPClients::EthonHTTPRequest.new(Ethon::Easy.new(url: 'not a real URL'))
  end

  # HttpClientTestCases required method
  def test_delete
    perform_easy_request(default_url, :delete)
  end

  # HttpClientTestCases required method
  def test_head
    perform_easy_request(default_url, :head)
  end

  # HttpClientTestCases required method
  def test_put
    perform_easy_request(default_url, :put)
  end

  # HttpClientTestCases required method
  def timeout_error_class
    ::NewRelic::LanguageSupport.constantize(NewRelic::Agent::Instrumentation::Ethon::Easy::NOTICEABLE_ERROR_CLASS)
  end

  # HttpClientTestCases required method
  def simulate_error_response
    e = Ethon::Easy.new
    e.http_request(default_url, :get, {})
    e.stub :headers, -> { raise timeout_error_class.new('timeout') } do
      e.perform
    end
    DummyResponse.new(e.response_body, e.response_headers)
  end

  # HttpClientTestCases required method
  def get_wrapped_response(url)
    e = Ethon::Easy.new
    e.http_request(url, :get, {})
    e.perform
    NewRelic::Agent::HTTPClients::EthonHTTPResponse.new(e)
  end

  # HttpClientTestCases required method
  def response_instance(headers = {})
    response = DummyResponse.new('', headers.inject(+"200\r\n") { |s, (k, v)| s += "#{k}: #{v}\r\n" })
    NewRelic::Agent::HTTPClients::EthonHTTPResponse.new(response)
  end
end
