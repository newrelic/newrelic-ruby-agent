# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This class acts like an Array with a fixed capacity that randomly samples
# from a stream of items such that the probability of each item being included
# in the Array is equal. It uses reservoir sampling in order to achieve this:
# http://xlinux.nist.gov/dads/HTML/reservoirSampling.html

module NewRelic
  module Agent
    class SampledBuffer
      attr_reader :seen, :capacity, :seen_lifetime, :captured_lifetime

      def initialize(capacity)
        @items = []
        @capacity = capacity
        @captured_lifetime = 0
        @seen = 0
        @seen_lifetime = 0
      end

      def reset
        @captured_lifetime += @items.size
        @seen_lifetime += @seen
        @items = []
        @seen = 0
      end

      def full?
        @items.size >= @capacity
      end

      # Like '<<', but returns the value of full?
      def append(x)
        (self << x).full?
      end

      def <<(x)
        @seen += 1
        if @items.size < @capacity
          @items << x
        else
          m = rand(@seen) # [0, @seen)
          if m < @capacity
            @items[m] = x
          else
            # discard current sample
          end
        end
        return self
      end

      def size
        @items.size
      end

      def to_a
        @items.dup
      end

      def capacity=(new_capacity)
        @capacity = new_capacity
        old_items = @items
        @items = []
        old_items.each { |i| self << i }
      end

      def sample_rate
        @seen > 0 ? (size.to_f / @seen) : 0.0
      end

      def sample_rate_lifetime
        @captured_lifetime > 0 ? (@captured_lifetime.to_f / @seen_lifetime) : 0.0
      end
    end
  end
end

