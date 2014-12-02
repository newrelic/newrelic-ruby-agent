# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class AttributeFilter
      DST_NONE = 0x0

      DST_TRANSACTION_EVENT = 1 << 0
      DST_TRANSACTION_TRACE = 1 << 1
      DST_ERROR_TRACE       = 1 << 2
      DST_BROWSER_AGENT     = 1 << 3

      DST_ALL = 0xF

      def initialize(config)
        @enabled_destinations = []

        @enabled_destinations << DST_TRANSACTION_TRACE if config[:'transaction_tracer.attributes.enabled']
        @enabled_destinations << DST_TRANSACTION_EVENT if config[:'transaction_events.attributes.enabled']
        @enabled_destinations << DST_ERROR_TRACE       if config[:'error_collector.attributes.enabled']
        @enabled_destinations << DST_BROWSER_AGENT     if config[:'browser_monitoring.attributes.enabled']

        @enabled_destinations.clear unless config[:'attributes.enabled']
      end

      def apply(attribute_name, desired_destinations)
        @enabled_destinations.inject(0) { |result, dest| dest | result }
      end
    end
  end
end
