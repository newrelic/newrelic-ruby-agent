# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

# The StreamingBuffer class provides an Enumerator to the standard Ruby Queue 
# class.  The enumerator is blocking while the queue is empty.
module NewRelic::Agent
  module InfiniteTracing
    class StreamingBuffer
      include Enumerable
      
      SPANS_SEEN_METRIC   = "Supportability/InfiniteTracing/Span/Seen"
      SPANS_SENT_METRIC   = "Supportability/InfiniteTracing/Span/Sent"
      QUEUE_DUMPED_METRIC = "Supportability/InfiniteTracing/Span/AgentQueueDumped"

      DEFAULT_QUEUE_SIZE = 10_000        
      FLUSH_DELAY_LOOP = 0.005
      RESTART_TOKEN = Object.new.freeze

      def initialize max_size = DEFAULT_QUEUE_SIZE
        @max_size = max_size
        @restart_flag = false
        @restart_mutex = Mutex.new
        start_queue
      end

      def restart?
        @restart_flag
      end

      def empty?
        @queue.empty?
      end

      def waiting?
        wait_count > 0
      end

      def wait_count
        @queue.num_waiting
      end

      # Pushes the segment given onto the queue.  
      #
      # If the queue is at capacity, it is dumped and a 
      # supportability metric is recorded for the event.
      # 
      # When a restart signal is received, the queue is 
      # locked with a mutex, blocking the push until
      # the queue has restarted.
      def << segment
        @restart_mutex.synchronize do
          clear_queue if @queue.size >= @max_size

          NewRelic::Agent.increment_metric SPANS_SEEN_METRIC
          @queue.push segment
        end
      end

      # Drops all segments from the queue and records a
      # supportability metric for the event.
      def clear_queue
        @queue.clear
        NewRelic::Agent.increment_metric QUEUE_DUMPED_METRIC
      end

      # Waits for the queue to be fully consumed or for the 
      # waiting consumers to release.
      def flush_queue
        sleep(FLUSH_DELAY_LOOP) while !@queue.empty?
      end

      def close_queue
        unless @queue.closed?
          @queue.push(nil) if @queue.empty?
          @queue.close
        end
      end

      def finish
        @restart_mutex.synchronize do
          close_queue
          flush_queue
        end
      end

      def start_queue
        @queue = Queue.new
      end

      # Locks the queue before closing and restarting it
      def restart
        @restart_mutex.synchronize do
          @restart_flag = true
          close_queue
          start_queue
          @restart_flag = false
        end
      end

      # Implements a blocking enumerator on the queue.  
      # Loops indefinitely until +nil+ is popped from the queue.
      # (i.e. when popping the queue returns +nil+)
      #
      # A restart can be initiated at any point and indicates we need to 
      # re-establish a connection to the server.  As such, if we pop
      # during a restart event, the span is pushed back on the queue so
      # it may be sent over the new server connection.
      def each
        loop do
          # blocking pop waits until there's something to take off the queue
          if span = @queue.pop(false)
            # if restarting, push back on queue
            @queue.push(span) and raise ClosedQueueError if restart?

            # otherwise, yield the serializable span
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
        span_event = SpanEventPrimitive.for_segment segment
        Span.new Transformer.transform(span_event)
      end

    end
  end
end