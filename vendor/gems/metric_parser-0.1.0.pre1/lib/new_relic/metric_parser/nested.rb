# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module MetricParser
    class Nested < NewRelic::MetricParser::MetricParser
      def controller_name
        segments[3]
      end

      def action_name
        segments[4]
      end
    end
  end
end
