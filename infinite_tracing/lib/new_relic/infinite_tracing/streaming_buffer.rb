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
        start
      end

      def empty?
        @queue.empty?
      end

      def << segment
        NewRelic::Agent.increment_metric SPANS_SEEN_METRIC
        clear_queue if @queue.size >= @max_size
        @queue.push segment
      end

      def clear_queue
        @queue.clear
        NewRelic::Agent.increment_metric QUEUE_DUMPED_METRIC
      end

      def finish
        @queue.close
        sleep(FLUSH_DELAY_LOOP) while !@queue.empty?
      end

      def start
        @restart_flag = false
        @queue = Queue.new
      end

      def restart
        raise ClosedQueueError
        @restart_flag = true
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
          raise ClosedQueueError if restart?
          # Block pop waits until there's something to take off the queue
          if span = @queue.pop(false)
            # if a restart was received, put span back on queue and return nothing
            if restart?
              @queue.push span
              raise ClosedQueueError
            end

            NewRelic::Agent.increment_metric SPANS_SENT_METRIC
            yield transform(span)

          # popped nothing, so assume we're closing and return
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