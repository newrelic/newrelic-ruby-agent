# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class AttributeFilterRule
      attr_reader :attribute_name, :destinations, :is_include

      def initialize(attribute_name, destinations, is_include)
        @attribute_name = attribute_name.sub(/\*$/, "")
        @wildcard       = attribute_name.end_with?("*")
        @destinations   = destinations
        @is_include     = is_include
      end

      def <=>(other)
        name_cmp = @attribute_name <=> other.attribute_name
        return name_cmp unless name_cmp == 0

        if wildcard? != other.wildcard?
          return wildcard? ? -1 : 1
        end

        if is_include != other.is_include
          return is_include ? -1 : 1
        end

        return 0
      end

      def wildcard?
        @wildcard
      end

      def match?(name)
        if wildcard?
          name.start_with?(@attribute_name)
        else
          @attribute_name == name
        end
      end
    end


    class AttributeFilter
      DST_NONE = 0x0

      DST_TRANSACTION_EVENT = 1 << 0
      DST_TRANSACTION_TRACE = 1 << 1
      DST_ERROR_TRACE       = 1 << 2
      DST_BROWSER_AGENT     = 1 << 3

      DST_ALL = 0xF

      attr_reader :rules

      def initialize(config)
        @enabled_destinations = DST_NONE

        @enabled_destinations |= DST_TRANSACTION_TRACE if config[:'transaction_tracer.attributes.enabled']
        @enabled_destinations |= DST_TRANSACTION_EVENT if config[:'transaction_events.attributes.enabled']
        @enabled_destinations |= DST_ERROR_TRACE       if config[:'error_collector.attributes.enabled']
        @enabled_destinations |= DST_BROWSER_AGENT     if config[:'browser_monitoring.attributes.enabled']

        @enabled_destinations = DST_NONE unless config[:'attributes.enabled']

        @rules = []

        build_rule(config[:'attributes.exclude'], DST_ALL, false)
        build_rule(config[:'transaction_tracer.attributes.exclude'], DST_TRANSACTION_TRACE, false)
        build_rule(config[:'transaction_events.attributes.exclude'], DST_TRANSACTION_EVENT, false)
        build_rule(config[:'error_collector.attributes.exclude'],    DST_ERROR_TRACE,       false)
        build_rule(config[:'browser_monitoring.attributes.exclude'], DST_BROWSER_AGENT,     false)

        build_rule(config[:'attributes.include'], DST_ALL, true)
        build_rule(config[:'transaction_tracer.attributes.include'], DST_TRANSACTION_TRACE, true)
        build_rule(config[:'transaction_events.attributes.include'], DST_TRANSACTION_EVENT, true)
        build_rule(config[:'error_collector.attributes.include'],    DST_ERROR_TRACE,       true)
        build_rule(config[:'browser_monitoring.attributes.include'], DST_BROWSER_AGENT,     true)

        @rules.sort!
      end

      def build_rule(attribute_names, destinations, is_include)
        attribute_names.each do |attribute_name|
          @rules << AttributeFilterRule.new(attribute_name, destinations, is_include)
        end
      end

      def apply(attribute_name, desired_destinations)
        destinations = @enabled_destinations
        return DST_NONE if destinations == DST_NONE

        destinations &= desired_destinations

        @rules.each do |rule|
          if rule.match?(attribute_name)
            if rule.is_include
              destinations |= (rule.destinations & @enabled_destinations)
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
