# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

module NewRelic
  module Agent
    module InfiniteTracing
      class StreamingBufferTest < Minitest::Test
        def setup
          @threads = {}
          NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
        end

        def teardown
          reset_buffers_and_caches
        end

        def test_streams_single_segment
          with_serial_lock do
            total_spans = 1
            buffer, _segments = stream_segments total_spans
            consume_spans buffer

            refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
              "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
            })
          end
        end

        def test_streams_single_segment_in_threads
          with_serial_lock do
            total_spans = 1
            generator, buffer, _segments = prepare_to_stream_segments total_spans

            # consumes the queue as it fills
            _spans, consumer = prepare_to_consume_spans buffer

            generator.join
            buffer.flush_queue
            consumer.join

            refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
              "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
            })
            assert_watched_threads_finished buffer
          end
        end

        def test_streams_multiple_segments
          with_serial_lock do
            total_spans = 5
            buffer, segments = stream_segments total_spans

            spans = consume_spans buffer

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
        end

        def test_streams_multiple_segments_in_threads
          with_serial_lock do
            total_spans = 5
            generator, buffer, segments = prepare_to_stream_segments total_spans

            # consumes the queue as it fills
            spans, consumer = prepare_to_consume_spans buffer

            generator.join
            buffer.flush_queue
            consumer.join

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
        end

        def test_drops_queue_when_max_reached
          with_serial_lock do
            total_spans = 9
            max_queue_size = 4

            # generate all spans before we attempt to consume
            buffer, segments = stream_segments total_spans, max_queue_size

            # consumes the queue after we've filled it
            spans = consume_spans buffer

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
        end

        def test_can_close_an_empty_buffer
          with_serial_lock do
            total_spans = 10
            generator, buffer, segments = prepare_to_stream_segments total_spans

            # consumes the queue as it fills
            spans, consumer = prepare_to_consume_spans buffer

            # closes the streaming buffer after queue is emptied
            closed = false
            emptied = false
            closer = watch_thread(:closer) do
              loop do
                if spans.size == total_spans
                  emptied = buffer.empty?
                  closed = true
                  break
                end
              end
            end

            closer.join
            generator.join
            buffer.flush_queue
            consumer.join

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
        end

        private

        def assert_watched_threads_finished buffer
          @threads.each do |thread_name, thread|
            refute thread.alive?, "Thread #{thread_name} is still alive #{buffer.num_waiting}!"
          end
        end

        def process_threads
          @threads.each(&:join)
        end

        def watch_thread name, &block
          @threads[name] = Thread.new(&block)
        end

        def prepare_to_consume_spans buffer, sleep_delay = 0
          spans = []
          consumer = watch_thread(:consumer) { buffer.enumerator.each { |span| spans << span } }

          return spans, consumer
        end

        # pops all the serializable spans off the buffer and returns them.
        def consume_spans buffer
          buffer.enumerator.map(&:itself)
        end

        # starts a watched thread that will generate segments asynchronously.
        def prepare_to_stream_segments count, max_buffer_size = 100_000
          buffer = StreamingBuffer.new max_buffer_size
          segments = []

          # generates segments that are streamed as spans
          generator = watch_thread(:generator) do
            count.times do
              with_segment do |segment|
                segments << segment
                buffer << deferred_span(segment)
              end
            end
          end

          return generator, buffer, segments
        end

        # Opens a streaming buffer,enqueues count segments to the buffer
        # closes the queue when done as we assume no more will be
        # generated and don't want to block indefinitely.
        #
        # Returns the buffer with segments on the queue as well
        # as the segments that were generated separately.
        def stream_segments count, max_buffer_size = 100_000
          buffer = StreamingBuffer.new max_buffer_size
          segments = []

          # generates segments that are streamed as spans
          count.times do
            with_segment do |segment|
              segments << segment
              buffer << deferred_span(segment)
            end
          end

          # if we don't close, we block the pop
          # in the enumerator indefinitely
          buffer.close_queue

          return buffer, segments
        end
      end
    end
  end
end
