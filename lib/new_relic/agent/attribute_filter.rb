# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    AttributeFilterRule = Struct.new(:attribute_name, :destinations, :is_include)

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

        @rules = []

        build_exclusion(config[:'attributes.exclude'], DST_ALL)
        build_exclusion(config[:'transaction_tracer.attributes.exclude'], DST_TRANSACTION_TRACE)
        build_exclusion(config[:'transaction_events.attributes.exclude'], DST_TRANSACTION_EVENT)
        build_exclusion(config[:'error_collector.attributes.exclude'], DST_ERROR_TRACE)
        build_exclusion(config[:'browser_monitoring.attributes.exclude'], DST_BROWSER_AGENT)
      end

      def build_exclusion(exclude_names, destinations)
        exclude_names.each do |attribute_name|
          @rules << AttributeFilterRule.new(attribute_name, destinations, false)
        end
      end

      def apply(attribute_name, desired_destinations)
        destinations = @enabled_destinations.inject(DST_NONE) { |result, dest| dest | result }

        @rules.each do |rule|
          if rule.attribute_name == attribute_name
            if rule.is_include
            else
              destinations &= ~rule.destinations
            end
          end
        end

        destinations
      end
    end
  end
end
