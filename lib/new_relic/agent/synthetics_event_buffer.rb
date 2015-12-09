# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sized_buffer'

module NewRelic
  module Agent
    class SyntheticsEventBuffer < SizedBuffer

      def append_with_reject(x)
        @seen += 1
        if full?
          timestamp = timestamp_for(x)
          latest_event = @items.max_by do |item|
            timestamp_for(item)
          end

          if timestamp < timestamp_for(latest_event)
            # Make room!
            @items.delete(latest_event)
            return [append_event(x), latest_event]
          else
            return [nil, x]
          end
        else
          return [append_event(x), nil]
        end
      end

      TIMESTAMP = "timestamp".freeze

      def timestamp_for(event)
        main_event, _ = event
        main_event[TIMESTAMP]
      end
    end
  end
end

