# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/heap'

module NewRelic
  module Agent
    class TimestampSampledBuffer < PrioritySampledBuffer
      TIMESTAMP_KEY = "timestamp".freeze

      private

      def priority_for(event)
        -event[0][TIMESTAMP_KEY]
      end
    end
  end
end
