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
  DummyResponse = Struct.new(:body)

  # Don't bother with CAT for Ethon - undefine all of the tests requiring CAT
  # Also, Ethon's instrumentation doesn't use a response wrapper, as it's
  # primarily used for CAT headers, so undefine the response wrapper based tests
  # as well
  load_cross_agent_test('cat_map').map { |t| define_method("test_#{t['name']}") {} }
  load_cross_agent_test('synthetics/synthetics').map { |t| define_method("test_synthetics_http_#{t['name']}") {} }
  %i[test_adds_a_request_header_to_outgoing_requests_if_xp_enabled
    test_adds_a_request_header_to_outgoing_requests_if_old_xp_config_is_present
    test_adds_newrelic_transaction_header
    test_validate_response_wrapper
    test_status_code_is_present
    test_response_headers_for_missing_key
    test_response_wrapper_ignores_case_in_header_keys
    test_agent_doesnt_add_a_request_header_to_outgoing_requests_if_xp_disabled
    test_agent_doesnt_add_a_request_header_if_empty_cross_process_id
    test_agent_doesnt_add_a_request_header_if_empty_encoding_key
    test_instrumentation_with_crossapp_enabled_records_normal_metrics_if_no_header_present
    test_instrumentation_with_crossapp_disabled_records_normal_metrics_even_if_header_is_present
    test_instrumentation_with_crossapp_enabled_records_crossapp_metrics_if_header_present
    test_crossapp_metrics_allow_valid_utf8_characters
    test_crossapp_metrics_ignores_crossapp_header_with_malformed_cross_process_id
    test_raw_synthetics_header_is_passed_along_if_present
    test_no_raw_synthetics_header_if_not_present].each do |test|
    define_method(test) {}
  end

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
      responses << DummyResponse.new(easy.response_body)
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
    DummyResponse.new(e.response_body)
  end

  def perform_easy_request(url, action, headers = nil)
    e = Ethon::Easy.new
    e.http_request(url, action, {})
    e.headers = headers if headers
    e.perform
    DummyResponse.new(e.response_body)
  end
end
