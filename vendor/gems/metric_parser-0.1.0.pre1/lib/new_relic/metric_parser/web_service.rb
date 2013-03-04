# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/metric_parser'
module NewRelic
  module MetricParser
    class WebService < NewRelic::MetricParser::MetricParser
      def is_web_service?
        segments[1] != 'Soap' && segments[1] != 'Xml Rpc'
      end

      def webservice_call_rate_suffix
        'rpm'
      end
    end
  end
end
