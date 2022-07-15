# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'grpc'
require 'newrelic_rpm'

class GrpcTest < Minitest::Test
  include MultiverseHelpers

  def setup
  end

  def teardown
  end

  # Tests
  # Test initialize_with_tracing
  # Test issue_request_with_tracing

  # test_blocklist_stops_newrelic_traffic

  # test_initialize_with_tracing_sets_trace_with_new_relic

  # test_intiailize_with_tracing_returns_instance

  # test_issue_request_with_tracing_captures_error

  # test_issue_request_with_tracing_adds_request_headers

  # test_issue_request_with_tracing_adds_request_headers

  # test_issue_request_with_tracing_creates_external_request_segment

  # test_method_uri_uses_correct_format

  # test_method_has_cleaned_name

  # test_request_not_traced_if_class_interceptor

  # test_bidi_streaming
  # test_request_response
  # test_server_streaming
  # test_client_streaming

end
