# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class StreamingBuffer
      include Enumerable
      
      attr_reader :seen, :sent, :max

      FLUSH_DELAY_LOOP = 0.005

      def initialize max_size = 10_000
        @max_size = max_size
        @semaphore = Mutex.new
        start
      end

      def << segment
        NewRelic::Agent.increment_metric("Supportability/InfiniteTracing/Span/Seen")
        clear_queue if @queue.size >= @max_size
        @queue.push segment
      end

      def clear_queue
        @queue.clear
        NewRelic::Agent.increment_metric("Supportability/InfiniteTracing/Span/AgentQueueDumped")
      end

      # Also call SpanEventPrimative decorators!
      def transform segment
        span_event = NewRelic::Agent::SpanEventPrimitive.for_segment segment
        annotated_span = Transformer.transform span_event
        Com::Newrelic::Trace::V1::Span.new annotated_span
      end

      def finish
        @queue.close
        sleep(FLUSH_DELAY_LOOP) while !@queue.empty?
      end

      def start
        @queue = Queue.new
      end

      def each
        loop do
          if span = @queue.pop(false)
            NewRelic::Agent.increment_metric("Supportability/InfiniteTracing/Span/Sent")
            yield transform(span)
          else
            return
          end
        end
      end
    end
  end
end