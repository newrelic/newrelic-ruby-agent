# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

require 'new_relic/agent/attribute_filter'
require 'pp'

module NewRelic::Agent
  class AttributeFilterTest < Minitest::Test
    def test_all_the_things
      test_cases = load_cross_agent_test("attribute_configuration")
      test_cases.each do |test_case|
        puts "Testing #{test_case['testname']}"

        with_config(test_case['config']) do
          filter = AttributeFilter.new(NewRelic::Agent.config)

          attribute_name            = test_case['input_key']
          desired_destination_names = test_case['input_default_destinations']

          desired_destinations  = to_bitfield(desired_destination_names)
          actual_destinations   = filter.apply(attribute_name, desired_destinations)
          expected_destinations = to_bitfield(test_case['expected_destinations'])

          assert_equal(to_names(expected_destinations), to_names(actual_destinations), PP.pp(test_case, "") + PP.pp(filter.rules, ""))
        end
      end
    end

    def to_names(bitfield)
      names = []

      names << 'transaction_events' if (bitfield & AttributeFilter::DST_TRANSACTION_EVENT) != 0
      names << 'transaction_tracer' if (bitfield & AttributeFilter::DST_TRANSACTION_TRACE) != 0
      names << 'error_collector'    if (bitfield & AttributeFilter::DST_ERROR_TRACE)       != 0
      names << 'browser_monitoring' if (bitfield & AttributeFilter::DST_BROWSER_AGENT)     != 0

      names
    end

    def to_bitfield(destination_names)
      bitfield = AttributeFilter::DST_NONE

      destination_names.each do |name|
        case name
        when 'transaction_events' then bitfield |= AttributeFilter::DST_TRANSACTION_EVENT
        when 'transaction_tracer' then bitfield |= AttributeFilter::DST_TRANSACTION_TRACE
        when 'error_collector'    then bitfield |= AttributeFilter::DST_ERROR_TRACE
        when 'browser_monitoring' then bitfield |= AttributeFilter::DST_BROWSER_AGENT
        end
      end

      bitfield
    end
  end
end
