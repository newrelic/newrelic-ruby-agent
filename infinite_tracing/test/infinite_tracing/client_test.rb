# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

module NewRelic
  module Agent
    module InfiniteTracing
      class ClientTest < Minitest::Test
        include FakeTraceObserverHelpers

        def test_streams_multiple_segments
          with_serial_lock do
            NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
            total_spans = 5
            spans, segments = emulate_streaming_segments total_spans

            assert_equal total_spans, spans.size
            assert_equal total_spans, segments.size
            spans.each_with_index do |span, index|
              assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
              assert_equal segments[index].transaction.trace_id, span["trace_id"]
            end

            refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
              "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
            })
          end
        end

        def test_streams_across_reconnects
          with_serial_lock do
            NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
            total_spans = 5
            spans, segments = emulate_streaming_segments total_spans do |client, current_segments|
              if current_segments.size == 3
                client.restart
              else
                simulate_server_response
              end
            end

            assert_equal total_spans, segments.size
            assert_equal total_spans, spans.size

            span_ids = spans.map { |s| s["trace_id"] }.sort
            segment_ids = segments.map { |s| s.transaction.trace_id }.sort

            assert_equal segment_ids, span_ids

            refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
              "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
            })
          end
        end

        def test_handles_server_disconnects
          with_serial_lock do
            unstub_reconnection
            Connection.any_instance.stubs(:retry_connection_period).returns(0)
            NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')

            total_spans = 5
            leftover_spans = 2

            spans, segments = emulate_streaming_segments total_spans do |client, current_segments|
              if current_segments.size == total_spans - leftover_spans
                # we do this here instead of server_proc because we are testing that if
                # the server restarts while the CLIENT is currently running, it
                # behaves as expected (since we just testing the client behavior)
                simulate_server_response GRPC::Ok.new
              else
                # we need to do this so the client streaming helpers know when
                # the mock server has done its thing
                simulate_server_response
              end
            end

            assert_equal total_spans, segments.size
            assert_equal total_spans, spans.size

            span_ids = spans.map { |s| s["trace_id"] }.sort
            segment_ids = segments.map { |s| s.transaction.trace_id }.sort

            assert_equal segment_ids, span_ids

            refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
              "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
            })
          end
        end

        def test_handles_server_error_responses
          with_serial_lock do
            NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
            connection = Connection.instance
            connection.stubs(:retry_connection_period).returns(0)

            total_spans = 2
            emulate_streaming_with_initial_error total_spans

            assert_metrics_recorded "Supportability/InfiniteTracing/Span/Sent"
            assert_metrics_recorded "Supportability/InfiniteTracing/Span/Response/Error"
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Seen" => {:call_count => total_spans},
              "Supportability/InfiniteTracing/Span/gRPC/PERMISSION_DENIED" => {:call_count => 1}
            })
          end
        end

        def test_handles_suspended_state
          with_serial_lock do
            NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
            connection = Connection.instance
            connection.stubs(:retry_connection_period).returns(0)

            total_spans = 5
            emulate_streaming_segments total_spans do |client, segments|
              if segments.size == 3
                simulate_server_response_shutdown GRPC::Unimplemented.new("i dont exist")
              else
                simulate_server_response
              end
            end

            assert_metrics_recorded "Supportability/InfiniteTracing/Span/gRPC/UNIMPLEMENTED"
            assert_metrics_recorded "Supportability/InfiniteTracing/Span/Sent"
            assert_metrics_recorded "Supportability/InfiniteTracing/Span/Response/Error"
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Seen" => {:call_count => total_spans},
              "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 3},
              "Supportability/InfiniteTracing/Span/gRPC/UNIMPLEMENTED" => {:call_count => 1}
            })
          end
        end

        def test_stores_spans_when_not_connected
          with_serial_lock do
            NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
            client = Client.new

            5.times do
              with_segment do |segment|
                client << deferred_span(segment)
              end
            end

            assert_equal 5, client.buffer.queue.length
          end
        end
      end
    end
  end
end
