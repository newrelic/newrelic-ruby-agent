# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

# The StreamingBuffer class provides an Enumerator to the standard Ruby Queue
# class.  The enumerator is blocking while the queue is empty.
module NewRelic::Agent
  module InfiniteTracing

    BATCH_SIZE = 100

    class StreamingBuffer
      include Constants
      include Enumerable
      extend Forwardable
      def_delegators :@queue, :empty?, :num_waiting, :push
      
      DEFAULT_QUEUE_SIZE = 10_000
      FLUSH_DELAY        = 0.005
      MAX_FLUSH_WAIT     = 3 # three seconds
      
      attr_reader :queue

      def initialize max_size = DEFAULT_QUEUE_SIZE
        @max_size = max_size
        @lock = Mutex.new
        @queue = Queue.new
        @batch = Array.new
      end

      # Dumps the contents of this streaming buffer onto 
      # the given buffer and closes the queue
      def transfer new_buffer
        @lock.synchronize do
          until @queue.empty? do new_buffer.push @queue.pop end
          @queue.close
        end
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
        @lock.synchronize do
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
        @queue.num_waiting.times { @queue.push nil }
        close_queue

        # Logs if we're throwing away spans because nothing's 
        # waiting to take them off the queue.
        if @queue.num_waiting == 0 && !@queue.empty?
          NewRelic::Agent.logger.warn "Discarding #{@queue.size} segments on Streaming Buffer"
          return
        end

        # Only wait a short while for queue to flush
        cutoff = Time.now + MAX_FLUSH_WAIT
        until @queue.empty? || Time.now >= cutoff do sleep(FLUSH_DELAY) end
      end

      def close_queue
        @lock.synchronize { @queue.close }
      end

      # Returns the blocking enumerator that will pop
      # items off the queue while any items are present
      # If +nil+ is popped, the queue is closing.
      #
      # The segment is transformed into a serializable 
      # span here so processing is taking place within
      # the gRPC call's thread rather than in the main 
      # application thread.
      def enumerator
        return enum_for(:enumerator) unless block_given?
        loop do
          if segment = @queue.pop(false)
            NewRelic::Agent.increment_metric SPANS_SENT_METRIC
            yield transform(segment)

          else
            raise ClosedQueueError
          end
        end
      end

      # Returns the blocking enumerator that will pop
      # items off the queue while any items are present
      # 
      # yielding is deferred until batch_size spans is 
      # reached.
      #
      # If +nil+ is popped, the queue is closing. A 
      # final yield on non-empty batch is fired.
      #
      # The segment is transformed into a serializable 
      # span here so processing is taking place within
      # the gRPC call's thread rather than in the main 
      # application thread.
      def batch_enumerator
        return enum_for(:enumerator) unless block_given?
        loop do
          if proc_or_segment = @queue.pop(false)
            NewRelic::Agent.increment_metric SPANS_SENT_METRIC
            @batch << transform(proc_or_segment)
            if @batch.size >= BATCH_SIZE
              yield SpanBatch.new(spans: @batch)
              @batch.clear
            end

          else
            yield SpanBatch.new(spans: @batch) unless @batch.empty?
            raise ClosedQueueError
          end
        end
      end

      private

      def span_event proc_or_segment
        if proc_or_segment.is_a?(Proc)
          proc_or_segment.call 
        else
          SpanEventPrimitive.for_segment(proc_or_segment)
        end
      end

      def transform proc_or_segment
        Span.new Transformer.transform(span_event proc_or_segment)
      end

    end
  end
end
