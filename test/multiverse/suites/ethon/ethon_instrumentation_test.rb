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

  # TODO: These tests are not currently working with Ethon
  #   - test_raw_synthetics_header_is_passed_along_when_cat_disabled
  #       - The header is not pulled from the current transaction at the time of the request being performed
  #   - test_noticed_error_at_segment_and_txn_on_error
  #       - Currently errors are only set on segments, not transactions
  #   - test_noticed_forbidden_error
  #       - Server is unreachable even by `curl`
  #       - a response_code is 0 is seen, an error is noted, but there's no 403 code
  #   - test_noticed_internal_server_error
  #       - Similar to the forbidden error.
  #       - response_code is 0, not 500
  %i[test_raw_synthetics_header_is_passed_along_when_cat_disabled
    test_noticed_error_at_segment_and_txn_on_error
    test_noticed_forbidden_error
    test_noticed_internal_server_error].each do |test|
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
  # TODO: for multi
  # def get_response_multi(uri, count)

  # end

  # HttpClientTestCases required method
  # NOTE that the request won't actually be performed; simply inspected
  def request_instance
    # TODO: confirm the NOTE above
    NewRelic::Agent::HTTPClients::EthonHTTPRequest.new(Ethon::Easy.new(url: 'https://newrelic.com'))
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
    get_response('http://localhost:666/evil')
  end

  def perform_easy_request(url, action, headers = nil)
    e = Ethon::Easy.new
    e.http_request(url, action, {})
    e.headers = headers if headers
    e.perform
    DummyResponse.new(e.response_body)
  end
end
