# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class SpanAttributeFilter
      DST_SPAN = AttributeFilter::DST_SPAN
      SPAN     = 'span'.freeze

      def initialize(global_filter)
        @gloal_filter = global_filter

        @cache = Hash.new do |h, k|
          permitted_destinations = global_filter.apply k, DST_SPAN
          h[k] = global_filter.allows? permitted_destinations, DST_SPAN
        end
      end

      def permits?(attribute_name)
        @cache[attribute_name]
      end
    end
  end
end
