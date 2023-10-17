# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'ethon'
require 'newrelic_rpm'
require 'http_client_test_cases'
require_relative '../../../../lib/new_relic/agent/http_clients/ethon_wrappers'

class EthonInstrumentationTest < Minitest::Test
  include HttpClientTestCases

  # Ethon::Easy#perform doesn't return a response object. Our Ethon
  # instrumentation knows that and works fine. But the shared HTTP
  # client test cases expect one, so we'll fake one.
  DummyResponse = Struct.new(:body, :response_headers)

  # TODO: needed for non-shared tests?
  # def setup
  #   @stats_engine = NewRelic::Agent.instance.stats_engine
  # end

  # TODO: needed for non-shared tests?
  # def teardown
  #   NewRelic::Agent.instance.stats_engine.clear_stats
  # end

  # TODO: non-shared tests to go here as driven by code coverage

  # HttpClientTestCases required method
  #   NOTE: only required for clients that support multi
  #   NOTE: this method must be defined publicly to satisfy the
  #         the shared tests' `respond_to?` check
  # TODO: Ethon::Multi testing
  def xget_response_multi(url, count)
    multi = Ethon::Multi.new
    easies = []
    count.times do
      easy = Ethon::Easy.new
      easy.http_request(url, :get, {})
      easies << easy
      multi.add(easy)
    end
    multi.perform
    easies.each_with_object([]) do |easy, responses|
      responses << e.response_headers.new(easy.response_body, easy.response_headers)
    end
  end

  private

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

  def perform_easy_request(url, action, headers = nil)
    e = Ethon::Easy.new
    e.http_request(url, action, {})
    e.headers = headers if headers
    e.perform
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
