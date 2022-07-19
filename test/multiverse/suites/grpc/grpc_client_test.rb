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
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
    assert_trace_with_newrelic_present(grpc_client_stub)
    assert grpc_client_stub.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_initialize_with_tracing_sets_trace_with_new_relic_false_with_blocked_host
    grpc_client_stub = ::GRPC::ClientStub.new('tracing.edge.nr-data.not.a.real.endpoint', :this_channel_is_insecure)
    assert_trace_with_newrelic_present(grpc_client_stub)
    refute grpc_client_stub.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_initialize_with_tracing_sets_trace_with_new_relic_without_host
    ::GRPC::ClientStub.stub(:name, 'GRPC::InterceptorRegistry') do
      grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
      refute grpc_client_stub.send(:trace_with_newrelic?)
    end
  end

  # Tests for issue_request_with_tracing
  def test_falsey_trace_with_newrelic_does_not_create_segment
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
    return_value = 'Dinosaurs looked like big birds'
    grpc_client_stub.instance_variable_set(TRACE_WITH_NEWRELIC, false)
    # NOTE: by passing nil for metadata, we are guaranteed to encounter an
    #       exception unless the early 'return yield' is hit as desired
    result = grpc_client_stub.issue_request_with_tracing(nil, nil, nil, nil,
      deadline: nil, return_op: nil, parent: nil, credentials: nil,
      metadata: nil) { return_value }
    assert_equal return_value, result
  end

  def test_new_relic_creates_and_finishes_segment
    in_transaction('gRPC client test transaction') do |txn|
      return_value = 'Dinosaurs looked like big birds'
      grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
      grpc_client_stub.instance_variable_set(TRACE_WITH_NEWRELIC, true)
      result = grpc_client_stub.issue_request_with_tracing(nil, nil, nil, nil,
        deadline: nil, return_op: nil, parent: nil, credentials: nil,
        metadata: {}) { return_value }
      assert_equal return_value, result

      # TODO:
      #   - make sure the segment has the desired attributes
      #   - make sure the metadata being passed to yield has the desired key/val pairs
      # segment = txn.current_segment
    end
  end

  def test_formats_a_grpc_uri_from_a_method_string
    host = 'Up!'
    method = 'Russell'
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
    grpc_client_stub.instance_variable_set(:@host, host)
    result = grpc_client_stub.send(:method_uri, method)
    assert_equal "grpc://#{host}/#{method}", result
  end

  def test_does_not_format_a_uri_unless_there_is_a_host
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
    grpc_client_stub.remove_instance_variable(:@host)
    assert_nil grpc_client_stub.send(:method_uri, 'a method')
  end

  def test_does_not_format_a_uri_unless_there_is_a_method
    grpc_client_stub = ::GRPC::ClientStub.new('0.0.0.0', :this_channel_is_insecure)
    grpc_client_stub.instance_variable_set(:@host, 'a host')
    assert_nil grpc_client_stub.send(:method_uri, nil)
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
