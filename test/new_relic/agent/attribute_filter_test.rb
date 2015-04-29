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

    def test_allows?
      with_all_enabled do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        default_destination = AttributeFilter::DST_ALL

        assert filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_EVENTS)
        assert filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_TRACER)
        assert filter.allows?(default_destination, AttributeFilter::DST_ERROR_COLLECTOR)
        assert filter.allows?(default_destination, AttributeFilter::DST_BROWSER_MONITORING)
      end
    end

    def test_allows_with_restricted_default_destination
      with_all_enabled do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        default_destination = AttributeFilter::DST_ERROR_COLLECTOR

        assert filter.allows?(default_destination, AttributeFilter::DST_ERROR_COLLECTOR)

        refute filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_EVENTS)
        refute filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_TRACER)
        refute filter.allows?(default_destination, AttributeFilter::DST_BROWSER_MONITORING)
      end
    end


    def test_allows_with_multiple_default_destinations
      with_all_enabled do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        default_destination = AttributeFilter::DST_ERROR_COLLECTOR|AttributeFilter::DST_TRANSACTION_TRACER

        assert filter.allows?(default_destination, AttributeFilter::DST_ERROR_COLLECTOR)
        assert filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_TRACER)

        refute filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_EVENTS)
        refute filter.allows?(default_destination, AttributeFilter::DST_BROWSER_MONITORING)
      end
    end

    def test_capture_params_false_adds_exclude_rule_for_request_parameters
      with_config(:capture_params => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply 'request.parameters.muggle', AttributeFilter::DST_NONE

        assert_destinations [], result
      end
    end

    def test_capture_params_true_allows_request_params_for_traces_and_errors
      with_config(:capture_params => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply 'request.parameters.muggle', AttributeFilter::DST_NONE

        assert_destinations ['transaction_tracer', 'error_collector'], result
      end
    end

    def test_resque_capture_params_false_adds_exclude_rule_for_request_parameters
      with_config(:'resque.capture_params' => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply 'job.resque.args.*', AttributeFilter::DST_NONE

        assert_destinations [], result
      end
    end

    def test_resque_capture_params_true_allows_request_params_for_traces_and_errors
      with_config(:'resque.capture_params' => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply 'job.resque.args.*', AttributeFilter::DST_NONE

        assert_destinations ['transaction_tracer', 'error_collector'], result
      end
    end

    def test_sidekiq_capture_params_false_adds_exclude_rule_for_request_parameters
      with_config(:'sidekiq.capture_params' => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply 'job.sidekiq.args.*', AttributeFilter::DST_NONE

        assert_destinations [], result
      end
    end

    def test_sidekiq_capture_params_true_allows_request_params_for_traces_and_errors
      with_config(:'sidekiq.capture_params' => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply 'job.sidekiq.args.*', AttributeFilter::DST_NONE

        assert_destinations ['transaction_tracer', 'error_collector'], result
      end
    end

    def test_might_allow_prefix_default_case
      filter = AttributeFilter.new(NewRelic::Agent.config)
      refute filter.might_allow_prefix?(:'request.parameters')
    end

    def test_might_allow_prefix_blanket_include
      with_config(:'attributes.include' => '*') do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        assert filter.might_allow_prefix?(:'request.parameters')
      end
    end

    def test_might_allow_prefix_general_include
      with_config(:'attributes.include' => 'request.*') do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        assert filter.might_allow_prefix?(:'request.parameters')
      end
    end

    def test_might_allow_prefix_prefix_include
      with_config(:'attributes.include' => 'request.parameters.*') do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        assert filter.might_allow_prefix?(:'request.parameters')
      end
    end

    def test_might_allow_prefix_prefix_include_tt_only
      with_config(:'transaction_tracer.attributes.include' => 'request.parameters.*') do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        assert filter.might_allow_prefix?(:'request.parameters')
      end
    end

    def test_might_allow_prefix_non_matching_include
      with_config(:'transaction_tracer.attributes.include' => 'otherthing') do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        refute filter.might_allow_prefix?(:'request.parameters')
      end
    end

    def test_might_allow_prefix_more_specific_rule
      with_config(:'attributes.include' => 'request.parameters.lolz') do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        assert filter.might_allow_prefix?(:'request.parameters')
      end
    end

    def test_might_allow_prefix_more_specific_rule_with_wildcard
      with_config(:'attributes.include' => 'request.parameters.lolz.*') do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        assert filter.might_allow_prefix?(:'request.parameters')
      end
    end

    def assert_destinations(expected, result)
      assert_equal to_bitfield(expected), result, "Expected #{expected}, got #{to_names(result)}"
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

    def with_all_enabled
      with_config(
        :'transaction_tracer.attributes.enabled' => true,
        :'transaction_events.attributes.enabled' => true,
        :'error_collector.attributes.enabled' => true,
        :'browser_monitoring.attributes.enabled' => true) do
        yield
      end
    end
  end
end
