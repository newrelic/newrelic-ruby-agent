# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class SuspendedStreamingBufferTest < Minitest::Test

        def setup
          @threads = {}
          NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
        end

        def teardown
          reset_buffers_and_caches
        end

        def test_streams_multiple_segments
          total_spans = 5
          buffer, segments = stream_segments total_spans

          spans = consume_spans buffer

          assert_equal 0, spans.size
          spans.each_with_index do |span, index|
            assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
            assert_equal segments[index].transaction.trace_id, span["trace_id"]
          end

          refute_metrics_recorded([
            "Supportability/InfiniteTracing/Span/AgentQueueDumped",
            "Supportability/InfiniteTracing/Span/Sent"
          ])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => total_spans},
          })
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
            timeout_cap do
              loop do
                if segments.size == total_spans
                  emptied = buffer.empty?
                  closed = true
                  break
                end
              end
            end
          end

          closer.join
          generator.join
          buffer.flush_queue

          assert emptied, "spans streamed reached total but buffer not empty!"
          assert closed, "failed to close the buffer"
          assert_equal total_spans, segments.size
          assert_equal 0, spans.size

          refute_metrics_recorded([
            "Supportability/InfiniteTracing/Span/AgentQueueDumped",
            "Supportability/InfiniteTracing/Span/Sent"
          ])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => total_spans},
          })
          assert_watched_threads_finished buffer
        end

        private

        def assert_watched_threads_finished buffer
          @threads.each do |thread_name, thread|
            refute thread.alive?, "Thread #{thread_name} is still alive!"
          end
        end

        def process_threads
          @threads.each(&:join)
        end

        def watch_thread name, &block
          @threads[name] = Thread.new(&block)
        end

        def prepare_to_consume_spans buffer, sleep_delay=0
          spans = []
          consumer = watch_thread(:consumer) { buffer.enumerator.each{ |span| spans << span } }

          return spans, consumer
        end

        # pops all the serializable spans off the buffer and returns them.
        def consume_spans buffer
          buffer.enumerator.map(&:itself)
        end          

        # starts a watched thread that will generate segments asynchronously.
        def prepare_to_stream_segments count, max_buffer_size=100_000
          buffer = SuspendedStreamingBuffer.new max_buffer_size
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
        def stream_segments count, max_buffer_size=100_000
          buffer = SuspendedStreamingBuffer.new max_buffer_size
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
