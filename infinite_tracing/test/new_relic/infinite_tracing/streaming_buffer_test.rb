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
          buffer = StreamingBuffer.new
          segment, txn = with_segment do |segment|
            buffer << segment
          end            

          t = Thread.new { buffer.finish }

          buffer.each do |span|
            assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
            assert_equal txn.trace_id, span["trace_id"]
          end
          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
          })
        end

        def test_streams_multiple_segments
          buffer = StreamingBuffer.new
          segments = []
          5.times do
            segment, txn = with_segment { |segment| buffer << segment }
            segments << segment
          end            

          t = Thread.new { buffer.finish }

          spans = []
          buffer.each do |span|
            spans << span
          end
          assert_equal 5, spans.size
          spans.each do |span|
            assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
          end
          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
          })
        end
       
        def test_drops_queue_when_max_reached
          buffer = StreamingBuffer.new 4
          segments = []
          9.times do
            segment, txn = with_segment { |segment| buffer << segment }
            segments << segment
          end            

          t = Thread.new { buffer.finish }

          spans = []
          buffer.each do |span|
            spans << span
          end
          assert_equal 1, spans.size
          assert_equal segments[-1].transaction.trace_id, spans[0]["trace_id"]
          assert_equal segments[-1].transaction.trace_id, spans[0]["intrinsics"]["traceId"].string_value

          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 9},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/AgentQueueDumped" => {:call_count => 2}
          })
        end
       
      end
    end
  end
end
