# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/heap'

module NewRelic
  module Agent
    class PrioritySampledBuffer < SampledBuffer
      PRIORITY_KEY = "priority".freeze

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
          @items = Heap.new(@items) { |x| priority_for(x) }
        end

        if full?
          priority ||= priority_for(event)
          if priority_for(@items[0]) < priority
            @items[0] = event || blk.call
            @items.fix(0)
          end
        else
          @items << (event || blk.call)
          @captured_lifetime += 1
        end
      end

      alias_method :append_event, :append

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

      private

      def increment_seen
        @seen += 1
        @seen_lifetime += 1
      end

      def priority_for(event)
        event[0][PRIORITY_KEY]
      end
    end
  end
end

