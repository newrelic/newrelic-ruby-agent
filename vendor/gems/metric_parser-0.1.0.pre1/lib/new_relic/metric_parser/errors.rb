# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  autoload :MetricParser, 'new_relic/metric_parser'
  module MetricParser
    class Errors < NewRelic::MetricParser::MetricParser
      def is_error?; true; end
      def short_name
        segments[2..-1].join(NewRelic::MetricParser::MetricParser::SEPARATOR)
      end
    end
  end
end
