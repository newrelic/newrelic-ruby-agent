# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'test_helper'

module NewRelic
  module Agent
    module InfiniteTracing
      class StreamingBufferTest < Minitest::Test

        def teardown
          reset_buffers_and_caches
        end

        def test_streams_single_segment
          buffer, segments = emulate_streaming_segments 1

          buffer.each do |span|
            assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
            assert_equal segments[0].transaction.trace_id, span["trace_id"]
          end

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
          })
        end

        def test_streams_multiple_segments
          buffer, segments = emulate_streaming_segments 5

          spans = buffer.map(&:itself)

          assert_equal 5, spans.size
          spans.each{ |span| assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span }

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
          })
        end
       
        def test_drops_queue_when_max_reached
          buffer, segments = emulate_streaming_segments 9, 4

          spans = buffer.map(&:itself)

          assert_equal 1, spans.size
          assert_equal segments[-1].transaction.trace_id, spans[0]["trace_id"]
          assert_equal segments[-1].transaction.trace_id, spans[0]["intrinsics"]["traceId"].string_value

          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 9},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/AgentQueueDumped" => {:call_count => 2}
          })
        end

        private

        def emulate_streaming_segments count, max_buffer_size=100_000
          buffer = StreamingBuffer.new max_buffer_size
          segments = []
          count.times do |index|
            with_segment do |segment|
              segments << segment
              buffer << segment
            end
          end
          Thread.new { buffer.finish }
          return buffer, segments
        end
       
      end
    end
  end
end
