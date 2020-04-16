# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class StreamingBufferTest < Minitest::Test

        def setup
          @threads = {}
        end

        def teardown
          reset_buffers_and_caches
        end

        def test_streams_single_segment
          total_spans = 1
          generator, buffer, _segments = prepare_to_stream_segments total_spans

          # consumes the queue as it fills
          prepare_to_consume_spans buffer

          generator.join
          buffer.finish

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
          })
          assert_watched_threads_finished buffer
        end

        def test_streams_multiple_segments
          total_spans = 5
          generator, buffer, segments = prepare_to_stream_segments total_spans

          # consumes the queue as it fills
          spans, _consumer = prepare_to_consume_spans buffer

          generator.join
          buffer.finish

          assert_equal total_spans, spans.size
          spans.each_with_index do |span, index|
            assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
            assert_equal segments[index].transaction.trace_id, span["trace_id"]
          end

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => total_spans},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => total_spans}
          })
          assert_watched_threads_finished buffer
        end

        def test_drops_queue_when_max_reached
          total_spans = 9
          max_queue_size = 4
          generator, buffer, segments = prepare_to_stream_segments total_spans, max_queue_size

          generator.join
          
          sleep(0.001) while generator.alive?

          # consumes the queue as it fills
          spans, _consumer = prepare_to_consume_spans buffer
          buffer.finish

          assert_equal 1, spans.size
          assert_equal segments[-1].transaction.trace_id, spans[0]["trace_id"]
          assert_equal segments[-1].transaction.trace_id, spans[0]["intrinsics"]["traceId"].string_value

          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 9},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/AgentQueueDumped" => {:call_count => 2}
          })
          assert_watched_threads_finished buffer
        end

        def test_nothing_dropped_when_restarted_mid_consumption
          total_spans = 9
          generator, buffer, _segments = prepare_to_stream_segments total_spans

          # consumes the queue as it fills
          spans, _consumer = prepare_to_consume_spans buffer

          # restarts the streaming buffer after a few were streamed
          restarted = false
          fully_consumed = false
          watch_thread(:restarter) do 
            loop do
              if spans.size > 3
                restarted = true
                fully_consumed = spans.size == total_spans
                buffer.restart
                break
              end
            end
          end

          generator.join

          # restarting also means restarting the consumer
          # (i.e. reconnecting to gRPC server)
          more_spans, _consumer = prepare_to_consume_spans buffer
          buffer.finish

          assert_equal total_spans, spans.size + more_spans.size

          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => total_spans},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => total_spans},
          })

          assert restarted, "failed to restart!"
          refute fully_consumed, "all spans consumed before restarting"
          assert_watched_threads_finished buffer
        end

        def test_can_close_an_empty_buffer
          total_spans = 10
          generator, buffer, segments = prepare_to_stream_segments total_spans

          # consumes the queue as it fills
          spans, _consumer = prepare_to_consume_spans buffer

          # closes the streaming buffer after queue is emptied
          closed = false
          emptied = false
          closer = watch_thread(:closer) do 
            loop do
              if spans.size == total_spans 
                emptied = buffer.empty?
                closed = true
                buffer.finish
                break
              end
            end
          end

          closer.join
          generator.join

          assert emptied, "spans streamed reached total but buffer not empty!"
          assert closed, "failed to close the buffer"
          assert_equal total_spans, segments.size
          assert_equal total_spans, spans.size

          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => total_spans},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => total_spans}
          })
          assert_watched_threads_finished buffer
        end

        private

        def assert_watched_threads_finished buffer
          # wait_for_running_threads
          @threads.each do |thread_name, thread|
            refute thread.alive?, "Thread #{thread_name} is still alive #{ buffer.wait_count}!"
          end
        end

        def wait_for_running_threads
          @threads.each(&:join)
        end

        def watch_thread name, &block
          @threads[name] = Thread.new(&block)
        end

        def prepare_to_consume_spans buffer
          spans = []
          consumer = watch_thread(:consumer) { buffer.each{ |span| spans << span } }

          return spans, consumer
        end          

        def prepare_to_stream_segments count, max_buffer_size=100_000
          buffer = StreamingBuffer.new max_buffer_size
          segments = []

          # generates segments that are streamed as spans
          generator = watch_thread(:generator) do
            count.times do |each_with_index7|
              with_segment do |segment|
                segments << segment
                buffer << segment
              end
              Thread.pass # avoids intermittent failures
            end
          end
          
          return generator, buffer, segments
        end

      end
    end
  end
end
