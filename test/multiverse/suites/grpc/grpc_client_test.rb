# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'grpc'
require 'newrelic_rpm'

class GrpcClientTest < Minitest::Test
  include MultiverseHelpers

  # Helpers
  TRACE_WITH_NEWRELIC = :@trace_with_newrelic
  HOST = '0.0.0.0:5000'
  CHANNEL = :this_channel_is_insecure
  METHOD = 'routeguide.RouteGuide/GetFeature'

  def exception_class
    ::GRPC::Unknown
  end

  def basic_grpc_client
    ::GRPC::ClientStub.new(HOST, CHANNEL)
  end

  def trace_with_newrelic_true(grpc_client)
    grpc_client.instance_variable_set(TRACE_WITH_NEWRELIC, true)
  end

  def successful_grpc_client_issue_request_with_tracing(metadata = {})
    in_transaction('gRPC client test transaction') do |txn|
      grpc_client = basic_grpc_client
      trace_with_newrelic_true(grpc_client)
      result = grpc_client.issue_request_with_tracing(
        nil,
        METHOD,
        nil,
        nil,
        nil,
        deadline: nil,
        return_op: nil,
        parent: nil,
        credentials: nil,
        metadata: metadata
      ) { '' }
    end
  end

  ## Tests
  def test_trace_by_default
    client = basic_grpc_client
    assert client.send(:trace_with_newrelic?)
    assert client.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_do_not_trace_interceptors
    client = basic_grpc_client
    def client.interceptor?; true; end
    refute client.send(:trace_with_newrelic?)
    refute client.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_do_not_trace_when_a_denylisted_host_is_involved
    client = ::GRPC::ClientStub.new('tracing.edge.nr-data.not.a.real.endpoint', CHANNEL)
    refute client.send(:trace_with_newrelic?)
    refute client.instance_variable_get(TRACE_WITH_NEWRELIC)
  end

  def test_falsey_trace_with_newrelic_does_not_create_segment
    return_value = 'Dinosaurs looked like big birds'
    grpc_client = basic_grpc_client
    grpc_client.instance_variable_set(TRACE_WITH_NEWRELIC, false)
    # NOTE: by passing nil for metadata, we are guaranteed to encounter an
    #       exception unless the early 'return yield' is hit as desired
    in_transaction('grpc test') do |txn|
      result = grpc_client.issue_request_with_tracing(nil, nil, nil, nil, nil,
        deadline: nil, return_op: nil, parent: nil, credentials: nil,
        metadata: nil) { return_value }
      assert_equal return_value, result
      # in_transaction always creates one segment, we don't want a second segment
      assert_equal 1, txn.segments.count
    end
  end

  def test_issue_request_with_tracing_returns_grpc_block
    return_value = 'Dinosaurs looked like big birds'
    grpc_client = basic_grpc_client
    transaction = NewRelic::Agent.instance.stub(:connected?, true) do
      in_transaction('gRPC client test transaction') do |txn|
        trace_with_newrelic_true(grpc_client)
        result = grpc_client.issue_request_with_tracing(
          nil,
          METHOD,
          nil,
          nil,
          nil,
          deadline: nil,
          return_op: nil,
          parent: nil,
          credentials: nil,
          metadata: {}
        ) { return_value }
        assert_equal return_value, result
      end
    end
  end

  def test_new_relic_creates_and_finishes_segment
    transaction = successful_grpc_client_issue_request_with_tracing

    assert_equal 2, transaction.segments.count
    segment = transaction.segments.last
    assert_includes segment.class.name, 'ExternalRequest'
    assert_includes segment.name, HOST
  end

  def test_distributed_tracing_payload_created
    metadata = {}
    # The agent must be connected to add DT headers
    transaction = NewRelic::Agent.instance.stub(:connected?, true) do
      successful_grpc_client_issue_request_with_tracing(metadata)
    end

    assert_newrelic_metadata_present(metadata)
    assert_distributed_tracing_payload_created_for_transaction(transaction)
  end

  def test_span_attributes_added
    successful_grpc_client_issue_request_with_tracing

    span = last_span_event
    assert 'gRPC', span[0]['component']
    assert METHOD, span[0]['http.method']
    assert "grpc://#{HOST}/#{METHOD}", span[2]['http.url']
  end

  def test_external_metric_recorded
    successful_grpc_client_issue_request_with_tracing
    assert_metrics_recorded("External/#{HOST}/gRPC/#{METHOD}")
  end

  def test_new_relic_captures_segment_error
    grpc_client = basic_grpc_client
    trace_with_newrelic_true(grpc_client)
    txn = nil

    begin
      in_transaction('gRPC client test transaction') do |local_txn|
        txn = local_txn
        grpc_client.issue_request_with_tracing(
          nil,
          METHOD,
          nil,
          nil,
          nil,
          deadline: nil,
          return_op: nil,
          parent: nil,
          credentials: nil,
          metadata: {}
        ) { raise exception_class.new }
      end
    rescue StandardError => e
      # NOP - Allowing error to be noticed
    end

    segment = txn.segments.last
    assert_segment_noticed_error txn, /gRPC/, exception_class.name, /2:unknown cause/i
    assert_transaction_noticed_error txn, exception_class.name
  end

  def test_formats_a_grpc_uri_from_a_method_string
    grpc_client = basic_grpc_client
    grpc_client.instance_variable_set(:@host, HOST)
    result = grpc_client.send(:method_uri, METHOD)
    assert_equal "grpc://#{HOST}/#{METHOD}", result
  end

  def test_does_not_format_a_uri_unless_there_is_a_host
    grpc_client = basic_grpc_client
    grpc_client.remove_instance_variable(:@host)
    assert_nil grpc_client.send(:method_uri, 'a method')
  end

  def test_does_not_format_a_uri_unless_there_is_a_method
    grpc_client = basic_grpc_client
    grpc_client.instance_variable_set(:@host, 'a host')
    assert_nil grpc_client.send(:method_uri, nil)
  end

  def test_gleaning_info_from_an_exception_returns_early
    exception = MiniTest::Mock.new
    exception.expect(:message, 'a message that does not match the expected format')
    refute basic_grpc_client.send(:grpc_status_and_message_from_exception, exception)
  end

  def test_gleaning_info_from_an_exception_works_correctly
    status = 2049
    message = "He reads, that's good. Me too, not much else to do around here at night anymore. Many is the night I " \
      'dream of cheese. Toasted, mostly. What are you doing here?'.gsub(/[,'\?\. ]/, '_')
    exception = MiniTest::Mock.new
    exception.expect(:message, "#{status}:#{message}. He liked to work alone. So did I. So we worked together to keep " \
                               'it that way.')
    assert_equal [status, message], basic_grpc_client.send(:grpc_status_and_message_from_exception, exception)
  end
end
