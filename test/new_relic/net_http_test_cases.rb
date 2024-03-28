# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'net/http'
require 'newrelic_rpm'
require 'http_client_test_cases'

module NetHttpTestCases
  include HttpClientTestCases

  #
  # Support for shared test cases
  #

  def client_name
    'Net::HTTP'
  end

  def timeout_error_class
    Net::ReadTimeout
  end

  def simulate_error_response
    Net::HTTP.any_instance.stubs(:transport_request).raises(timeout_error_class.new)
    get_response
  end

  def get_response(url = nil, headers = {})
    uri = default_uri
    uri = URI.parse(url) unless url.nil?
    path = uri.path.empty? ? '/' : uri.path

    start(uri) { |http| http.get(path, headers) }
  end

  def get_wrapped_response(url)
    NewRelic::Agent::HTTPClients::NetHTTPResponse.new(get_response(url))
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
    start(default_uri) { |http| http.post(default_uri.path, '') }
  end

  def put_response
    start(default_uri) { |http| http.put(default_uri.path, '') }
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
    headers.each do |k, v|
      response[k] = v
    end
    NewRelic::Agent::HTTPClients::NetHTTPResponse.new(response)
  end

  #
  # Net::HTTP specific tests
  #
  def test_get__simple
    # Don't check this specific condition against SSL, since API doesn't support it
    return if use_ssl?

    in_transaction do
      Net::HTTP.get(default_uri)
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
      'External/localhost/Net::HTTP/GET' => {:call_count => 1}
    )
  end

  def test_ipv6_host_get_request_records_metric
    http = Net::HTTP.new('::1', default_uri.port)
    in_transaction do
      http.request(Net::HTTP::Get.new('/status'))
    end

    assert_metrics_recorded(
      'External/[::1]/Net::HTTP/GET' => {:call_count => 1}
    )
  end

  class OpenAITestError < StandardError; end

  def test_does_not_attempt_to_populate_response_headers_without_openai
    segment = Minitest::Mock.new

    NewRelic::Agent::LLM.stub(:openai_parent?, false, segment) do
      # raise if populate_openai_response_headers is called
      NewRelic::Agent::LLM.stub(:populate_openai_response_headers, -> { raise OpenAITestError.new }) do
        in_transaction do
          get_response
        end
      end
    end
  end

  def test_attempts_to_populate_response_headers_with_openai
    segment = Minitest::Mock.new
    wrapped_response = Minitest::Mock.new
    mock_proc = proc { |*_args| raise OpenAITestError }
    result = nil
    expected_result = 'expected_result'

    NewRelic::Agent::LLM.stub(:openai_parent?, true, segment) do
      result = NewRelic::Agent::LLM.stub(:populate_openai_response_headers, mock_proc) do
        begin
          in_transaction do
            get_response
          end
        rescue OpenAITestError
          return expected_result
        end
      end
    end

    assert_equal expected_result, result
  end
end
