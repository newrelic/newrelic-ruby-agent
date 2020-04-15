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
        @closing = true
      end

      def start
        if @queue
          #todo?
        else
          @queue = Queue.new
        end
        # @closing = false
      end

      def restart
        # @closing = true
        if @queue.empty?
          @queue << RESTART_TOKEN unless @queue.closed?
        else
          @queue.close
          old_queue = @queue
          @queue = Queue.new
          @queue << RESTART_TOKEN
          @queue.push old_queue.pop until old_queue.empty?
          @queue.close if old_queue.closed?
        end
      end

      # Implements a blocking enumerator on the queue.  We loop indefinitely
      # until queue is closed (i.e. when popping the queue returns +nil+)
      #
      # @closing here indicates the Agent is reconnecting to the collector
      # server and possibly has a new config.  This requires also reconnecting
      # to the Trace Observer with new agent run token.
      def each
        loop do
          # Block pop waits until there's something to take off the queue
          if span = @queue.pop(false)

            return if span == RESTART_TOKEN

            # We popped a span from the queue, so update metrics and stream it
            NewRelic::Agent.increment_metric SPANS_SENT_METRIC
            yield transform(span)

          # popped nothing, so assume we're closing and return
          else
            return
          end
        end
      end

      private

      def transform segment
        span_event = NewRelic::Agent::SpanEventPrimitive.for_segment segment
        annotated_span = Transformer.transform span_event
        Com::Newrelic::Trace::V1::Span.new annotated_span
      end

      # pushes span back onto queue if it is not the restart token
      # and resets closing status (this is how we break the loop)
      # cleanly w/o data loss.
      def close_queue span
        @closing = false
      end

    end
  end
end