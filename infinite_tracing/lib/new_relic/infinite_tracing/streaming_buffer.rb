# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class StreamingBuffer
      include Enumerable
      
      SPANS_SEEN_METRIC   = "Supportability/InfiniteTracing/Span/Seen"
      SPANS_SENT_METRIC   = "Supportability/InfiniteTracing/Span/Sent"
      QUEUE_DUMPED_METRIC = "Supportability/InfiniteTracing/Span/AgentQueueDumped"
        
      FLUSH_DELAY_LOOP = 0.005
      RESTART_TOKEN = Object.new.freeze

      def initialize max_size = 10_000
        @max_size = max_size
        @queue = nil
        @restart_flag = false
        @restart_mutex = Mutex.new
        start
      end

      def empty?
        @queue.empty?
      end

      def << segment
        NewRelic::Agent.increment_metric SPANS_SEEN_METRIC
        @restart_mutex.synchronize do
          clear_queue if @queue.size >= @max_size
          @queue.push segment
        end
      end

      def clear_queue
        @queue.clear
        NewRelic::Agent.increment_metric QUEUE_DUMPED_METRIC
      end

      def close_queue
        @queue.push(nil) if waiting? && @queue.empty?
        @queue.close
      end

      def flush
        sleep(FLUSH_DELAY_LOOP) while !@queue.empty?
      end

      def finish
        @restart_mutex.synchronize do
          close_queue
          flush
        end
      end

      def start
        @queue = Queue.new
      end

      def restart
        @restart_flag = true
        @restart_mutex.synchronize do
          close_queue
          start
        end
        @restart_flag = false
      end

      def wait_count
        @queue.num_waiting
      end

      def waiting?
        @queue.num_waiting > 0
      end

      def restart?
        @restart_flag
      end

      # Implements a blocking enumerator on the queue.  We loop indefinitely
      # until queue is closed (i.e. when popping the queue returns +nil+)
      #
      # @closing here indicates the Agent is reconnecting to the collector
      # server and possibly has a new config.  This requires also reconnecting
      # to the Trace Observer with new agent run token.
      def each
        loop do
          # blocking pop waits until there's something to take off the queue
          if span = @queue.pop(false)
            @queue.push(span) and raise ClosedQueueError if restart?

            NewRelic::Agent.increment_metric SPANS_SENT_METRIC
            yield transform(span)

          # popped nothing, so assume we're closing...
          else
            raise ClosedQueueError
          end
        end
      end

      private

      def transform segment
        span_event = NewRelic::Agent::SpanEventPrimitive.for_segment segment
        annotated_span = Transformer.transform span_event
        Com::Newrelic::Trace::V1::Span.new annotated_span
      end

    end
  end
end