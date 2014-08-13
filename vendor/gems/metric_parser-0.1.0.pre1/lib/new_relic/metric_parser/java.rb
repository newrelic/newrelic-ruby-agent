# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/metric_parser/java_parser'
module NewRelic
  module MetricParser
    class Java < NewRelic::MetricParser::MetricParser
      include JavaParser
      def initialize(name)
        super
        if segments.length > 2
          self.extend NewRelic::MetricParser::JavaParser
        end
      end

      def pie_chart_label
        short_name
      end

      def tooltip_name
        developer_name
      end

      def full_class_name
        segment_1
      end

      def method_name
        segment_2
      end

    end
  end
end
