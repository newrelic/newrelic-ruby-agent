# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

require 'new_relic/agent/attribute_filter'
require 'pp'

module NewRelic::Agent
  class AttributeFilterTest < Minitest::Test
    test_cases = load_cross_agent_test("attribute_configuration")
    test_cases.each do |test_case|
      define_method("test_#{test_case['testname'].gsub(/\W/, "_")}") do
        with_config(test_case['config']) do
          filter = AttributeFilter.new(NewRelic::Agent.config)

          attribute_name            = test_case['input_key']
          desired_destination_names = test_case['input_default_destinations']

          desired_destinations  = to_bitfield(desired_destination_names)
          actual_destinations   = filter.apply(attribute_name, desired_destinations)
          expected_destinations = to_bitfield(test_case['expected_destinations'])

          assert_equal(to_names(expected_destinations), to_names(actual_destinations),
                       PP.pp(test_case, "") + PP.pp(filter.rules, ""))
        end
      end
    end

    def test_applies_to_single_destination
      with_config(
        :'transaction_tracer.attributes.enabled' => true,
        :'transaction_events.attributes.enabled' => true,
        :'error_collector.attributes.enabled' => true,
        :'browser_monitoring.attributes.enabled' => true) do

        filter = AttributeFilter.new(NewRelic::Agent.config)

        assert filter.applies?(:foo, AttributeFilter::DST_TRANSACTION_EVENTS)
        assert filter.applies?(:foo, AttributeFilter::DST_TRANSACTION_TRACER)
        assert filter.applies?(:foo, AttributeFilter::DST_ERROR_COLLECTOR)
        assert filter.applies?(:foo, AttributeFilter::DST_BROWSER_MONITORING)
      end
    end

    def test_applies_to_multiple_destinations
      with_config(
        :'transaction_tracer.attributes.enabled' => true,
        :'transaction_events.attributes.enabled' => true,
        :'error_collector.attributes.enabled' => true,
        :'browser_monitoring.attributes.enabled' => false) do

        filter = AttributeFilter.new(NewRelic::Agent.config)

        assert filter.applies?(:foo,
          AttributeFilter::DST_TRANSACTION_EVENTS |
          AttributeFilter::DST_TRANSACTION_TRACER |
          AttributeFilter::DST_ERROR_COLLECTOR
        )

        refute filter.applies?(:foo, AttributeFilter::DST_ALL)
      end
    end

    def to_names(bitfield)
      names = []

      names << 'transaction_events' if (bitfield & AttributeFilter::DST_TRANSACTION_EVENTS) != 0
      names << 'transaction_tracer' if (bitfield & AttributeFilter::DST_TRANSACTION_TRACER) != 0
      names << 'error_collector'    if (bitfield & AttributeFilter::DST_ERROR_COLLECTOR)    != 0
      names << 'browser_monitoring' if (bitfield & AttributeFilter::DST_BROWSER_MONITORING) != 0

      names
    end

    def to_bitfield(destination_names)
      bitfield = AttributeFilter::DST_NONE

      destination_names.each do |name|
        case name
        when 'transaction_events' then bitfield |= AttributeFilter::DST_TRANSACTION_EVENTS
        when 'transaction_tracer' then bitfield |= AttributeFilter::DST_TRANSACTION_TRACER
        when 'error_collector'    then bitfield |= AttributeFilter::DST_ERROR_COLLECTOR
        when 'browser_monitoring' then bitfield |= AttributeFilter::DST_BROWSER_MONITORING
        end
      end

      bitfield
    end
  end
end
