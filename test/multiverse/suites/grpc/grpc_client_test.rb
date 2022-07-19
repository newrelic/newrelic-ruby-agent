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

  # Helpers
  def assert_trace_with_newrelic_present(grpc_client_stub)
    assert grpc_client_stub.instance_variables.include?(TRACE_WITH_NEWRELIC), "Instance variable #{TRACE_WITH_NEWRELIC} not found"
  end

  # Tests
  # SimpleCov for this test file only

  TRACE_WITH_NEWRELIC = :@trace_with_newrelic

  # Test initialize_with_tracing
  def test_initialize_with_tracing_sets_trace_with_new_relic_true_when_host_present
    skip("check instance variable assignment on initialize after issue_request_with_tracing tests are written")
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
    assert_trace_with_newrelic_present(grpc_client_stub)
    assert grpc_client_stub.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_initialize_with_tracing_sets_trace_with_new_relic_false_with_blocked_host
    skip("check instance variable assignment on initialize after issue_request_with_tracing tests are written")

    grpc_client_stub = ::GRPC::ClientStub.new('observer.newrelic.com', :this_channel_is_insecure)
    assert_trace_with_newrelic_present(grpc_client_stub)
    refute grpc_client_stub.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_initialize_with_tracing_sets_trace_with_new_relic_without_host
    skip("check instance variable assignment on initialize after issue_request_with_tracing tests are written")

    ::GRPC::ClientStub.stub(:name, 'GRPC::InterceptorRegistry') do
      grpc_client_stub = ::GRPC::ClientStub.new('', :this_channel_is_insecure)
      assert_trace_with_newrelic_present(grpc_client_stub)
      refute grpc_client_stub.instance_variable_get(TRACE_WITH_NEWRELIC)
    end
  end

  # Tests for issue_request_with_tracing
  def test_falsey_trace_with_newrelic_does_not_create_segment
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)

    Fiber.stub(:yield, 4) do
      grpc_client_stub.instance_variable_set(TRACE_WITH_NEWRELIC, false)
      result = grpc_client_stub.issue_request_with_tracing(nil, nil, nil, nil, deadline: nil, return_op: nil, parent: nil, credentials: nil, metadata: nil) { 'hi' }
      assert_equal 'fake', result
    end
  end

  # test_issue_request_with_tracing_captures_error

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
