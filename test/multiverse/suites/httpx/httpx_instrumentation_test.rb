# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'httpx'
require 'newrelic_rpm'
require 'ostruct'
require 'http_client_test_cases'
require 'uri'
require_relative '../../../../lib/new_relic/agent/http_clients/httpx_wrappers'
require_relative '../../../test_helper'

class PhonySession
  include NewRelic::Agent::Instrumentation::HTTPX

  def initialize(responses = {})
    @responses = responses
  end
end

class HTTPXInstrumentationTest < Minitest::Test
  include HttpClientTestCases

  # NOTE: httpx errors are only ever set on the segment and not the transaction,
  #       so skip the test for a scenario of having a noticed error on both
  define_method(:test_noticed_error_at_segment_and_txn_on_error) {}

  def test_finish_without_response
    PhonySession.new.nr_finish_segment.call(nil, nil)
  end

  def test_finish_with_error
    request = Minitest::Mock.new
    request.expect :response, :the_response
    2.times { request.expect :hash, 1138 }

    error = if Gem::Version.new(::HTTPX::VERSION) >= Gem::Version.new('1.3.0')
      request.expect :options, ::HTTPX::Options.new({})
      ::HTTPX::ErrorResponse.new(request, StandardError.new)
    else
      ::HTTPX::ErrorResponse.new(request, StandardError.new, {})
    end
    responses = {request => error}

    segment = Minitest::Mock.new
    def segment.notice_error(_error); end
    def segment.process_response_headers(_wrappep); end
    NewRelic::Agent::Transaction::Segment.stub :finish, nil do
      PhonySession.new(responses).nr_finish_segment.call(request, segment)
    end
    segment.verify
  end

  private

  # HttpClientTestCases required method
  def client_name
    NewRelic::Agent::HTTPClients::HTTPXHTTPRequest::TYPE
  end

  # HttpClientTestCases required method
  def get_response(url = default_url, headers = {})
    HTTPX.get(url, headers: headers)
  end

  # HttpClientTestCases required method
  def post_response
    HTTPX.post(default_url)
  end

  # HttpClientTestCases required method
  def test_delete
    HTTPX.delete(default_url)
  end

  # HttpClientTestCases required method
  def test_head
    HTTPX.head(default_url)
  end

  # HttpClientTestCases required method
  def test_put
    HTTPX.put(default_url)
  end

  # HttpClientTestCases required method
  # NOTE that the request won't actually be performed; simply inspected
  def request_instance
    headers = {}
    mock_request = Minitest::Mock.new
    mock_request.expect :uri, URI.parse('https://newrelic.com')
    7.times { mock_request.expect :headers, headers }
    mock_request.expect :verb, 'GET'
    NewRelic::Agent::HTTPClients::HTTPXHTTPRequest.new(mock_request)
  end

  # HttpClientTestCases required method
  def timeout_error_class
    ::NewRelic::LanguageSupport.constantize(NewRelic::Agent::Instrumentation::HTTPX::NOTICEABLE_ERROR_CLASS)
  end

  # HttpClientTestCases required method
  def simulate_error_response
    HTTPX::Connection.any_instance.stubs(:consume).raises(HTTPX::Error.new(OpenStruct.new))
    get_response(default_url)
  end

  # HttpClientTestCases required method
  def get_wrapped_response(url)
    NewRelic::Agent::HTTPClients::HTTPXHTTPResponse.new(get_response(url))
  end

  # HttpClientTestCases required method
  def response_instance(response_headers = {})
    response = get_response(default_url)
    response.instance_variable_set(:@headers, response_headers)
    NewRelic::Agent::HTTPClients::HTTPXHTTPResponse.new(response)
  end
end
