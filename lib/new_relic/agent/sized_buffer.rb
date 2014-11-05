# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_buffer'

module NewRelic
  module Agent
    class SizedBuffer < EventBuffer

      def append_event(x)
        if @items.size < @capacity
          @items << x
          return x
        else
          return nil
        end
      end

    end
  end
end

