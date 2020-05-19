# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class ClientTest < Minitest::Test
        include FakeTraceObserverHelpers
        def test_streams_multiple_segments
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

        def test_streams_across_reconnects
          NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
          total_spans = 5
          spans, segments = emulate_streaming_segments total_spans do |client, segments|
            if segments.size == 3
              client.restart
            end
          end

          assert_equal total_spans, segments.size
          assert_equal total_spans, spans.size

          span_ids = spans.map{|s| s["trace_id"]}.sort
          segment_ids = segments.map{|s| s.transaction.trace_id}.sort

          assert_equal segment_ids, span_ids

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
          })
        end

        def test_handles_server_disconnects
          unstub_reconnection
          Connection.any_instance.stubs(:retry_connection_period).returns(0)
          NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')

          total_spans = 5
          leftover_spans = 2
          spans, segments = emulate_streaming_segments total_spans do |client, segments|
            if segments.size == total_spans - leftover_spans
              restart_fake_trace_observer_server
              client.restart
            end
          end

          assert_equal total_spans, segments.size
          assert_equal leftover_spans, spans.size

          span_ids = spans.map{|s| s["trace_id"]}.sort
          segment_ids = segments.slice(-leftover_spans, leftover_spans).map{|s| s.transaction.trace_id}.sort

          assert_equal segment_ids, span_ids

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
          })
        end

        def test_handles_server_error_responses
          NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
          connection = Connection.instance
          connection.stubs(:retry_connection_period).returns(0)

          num_spans = 2
          emulate_streaming_with_initial_error num_spans

          assert_metrics_recorded "Supportability/InfiniteTracing/Span/Sent"
          assert_metrics_recorded "Supportability/InfiniteTracing/Span/Response/Error"
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => num_spans},
            "Supportability/InfiniteTracing/Span/gRPC/PERMISSION_DENIED" => {:call_count => 1}
          })
        end

        def test_handles_suspended_state
          NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
          connection = Connection.instance
          connection.stubs(:retry_connection_period).returns(0)

          total_spans = 5
          spans, segments = emulate_streaming_segments total_spans do |client, segments|
            if segments.size == 3
              client.handle_error GRPC::Unimplemented.new "suspend me!"
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

        def test_stores_spans_when_not_connected
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
