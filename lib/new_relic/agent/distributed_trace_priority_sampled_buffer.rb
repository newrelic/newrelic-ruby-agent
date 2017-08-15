# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_buffer'
require 'set'

module NewRelic
  module Agent
    class DistributedTracePrioritySampledBuffer < SampledBuffer
      attr_reader :seen_lifetime, :captured_lifetime

      def initialize(capacity)
        @low_priority_indices = []
        @high_priority_indices = Set.new
        super
      end

      def append_sampled(x = nil)
        @seen += 1
        @seen_lifetime += 1
        if @items.size < @capacity
          x = yield if block_given?
          insert_high_priority x
        elsif !@low_priority_indices.empty?
          m = rand(@low_priority_indices.size)
          insert_high_priority x, @low_priority_indices.delete_at(m)
        else
          # the buffer is full, we should record a supportability metric
        end
      end

      def append_event(x = nil, &blk)
        raise ArgumentError, "Expected argument or block, but received both" if x && blk

        if @items.size < @capacity
          x = blk.call if block_given?
          insert_low_priority x
          @captured_lifetime += 1
          return x
        else
          m = rand(@seen) # [0, @seen)
          if m < @capacity
            x = blk.call if block_given?
            insert_low_priority x, m
            return x
          else
            # discard current sample
            return nil
          end
        end
      end

      def insert_low_priority x, index = @items.size
        @items[index] = x
        @low_priority_indices << index
      end

      def insert_high_priority x, index = @items.size
        @items[index] = x
        @high_priority_indices << index
      end
    end
  end
end

