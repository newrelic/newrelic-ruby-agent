# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/heap'

module NewRelic
  module Agent
    class PrioritySampledBuffer < EventBuffer
      attr_reader :seen_lifetime, :captured_lifetime

      def initialize(capacity)
        super
        @captured_lifetime = 0
        @seen_lifetime     = 0
      end

      # expects priority and a block, or an event as a hash with a `priority` key.
      def append(priority: nil, event: nil, &blk)
        increment_seen

        if @seen == @capacity
          @items = Heap.new(@items) { |x| x[:priority] }
        end

        if full?
          priority ||= event[:priority]
          if @items[0][:priority] < priority
            @items[0] = event || blk.call
            @items.fix(0)
          end
        else
          @items << (event || blk.call)
          @captured_lifetime += 1
        end
      end

      def capacity=(new_capacity)
        @capacity = new_capacity
        old_items = @items.to_a
        old_seen  = @seen
        reset!
        old_items.each { |i| append(event: i) }
        @seen     = old_seen
      end

      def to_a
        @items.to_a.dup
      end

      def sample_rate_lifetime
        @captured_lifetime > 0 ? (@captured_lifetime.to_f / @seen_lifetime) : 0.0
      end

      private

      def increment_seen
        @seen += 1
        @seen_lifetime += 1
      end
    end
  end
end

