# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/metric_parser/java_parser'
module NewRelic
  module MetricParser
    class StrutsResult < NewRelic::MetricParser::MetricParser
      include JavaParser

      def method_name
        "execute"
      end

      def full_class_name
        segment_1
      end

      def call_rate_suffix
        'cpm'
      end
    end
  end
end
