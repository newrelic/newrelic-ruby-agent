# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/metric_parser'

module NewRelic
  module MetricParser
    class Nested < Controller
      def initialize(name)
        name_without_prefix = name.gsub(/^Nested\//, '')
        super(name_without_prefix)
      end

      def is_web_transaction?
        false
      end

      def is_transaction?
        false
      end
    end
  end
end
