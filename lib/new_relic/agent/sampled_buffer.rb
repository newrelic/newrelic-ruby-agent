# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This class acts like an Array with a fixed capacity that randomly samples
# from a stream of items such that the probability of each item being included
# in the Array is equal. It uses reservoir sampling in order to achieve this:
# http://xlinux.nist.gov/dads/HTML/reservoirSampling.html

require 'new_relic/agent/event_buffer'

module NewRelic
  module Agent
    class SampledBuffer < EventBuffer
      attr_reader :seen_lifetime, :captured_lifetime

      def initialize(capacity)
        super
        @captured_lifetime = 0
        @seen_lifetime     = 0
      end

      def reset!
        @captured_lifetime += @items.size
        @seen_lifetime     += @seen
        super
      end

      def append_event(x)
        if @items.size < @capacity
          @items << x
          return x
        else
          m = rand(@seen) # [0, @seen)
          if m < @capacity
            @items[m] = x
            return x
          else
            # discard current sample
            return nil
          end
        end
      end

      def sample_rate_lifetime
        @captured_lifetime > 0 ? (@captured_lifetime.to_f / @seen_lifetime) : 0.0
      end
    end
  end
end

