# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

require 'new_relic/agent/attribute_filter'
require 'pp'

module NewRelic::Agent
  class AttributeFilterTest < Minitest::Test
    test_cases = load_cross_agent_test("attribute_configuration")
    test_cases.each do |test_case|
      define_method("test_#{test_case['testname'].gsub(/\W/, "_")}") do
        with_config(test_case['config']) do
          filter = AttributeFilter.new(NewRelic::Agent.config)

          attribute_name = test_case['input_key']
          desired_destination_names = test_case['input_default_destinations']

          desired_destinations = to_bitfield(desired_destination_names)
          actual_destinations = filter.apply(attribute_name, desired_destinations)
          expected_destinations = to_bitfield(test_case['expected_destinations'])

          assert_equal(to_names(expected_destinations), to_names(actual_destinations),
            PP.pp(test_case, String.new('')) + PP.pp(filter.rules, String.new('')))
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
        default_destination = AttributeFilter::DST_ERROR_COLLECTOR | AttributeFilter::DST_TRANSACTION_TRACER

        assert filter.allows?(default_destination, AttributeFilter::DST_ERROR_COLLECTOR)
        assert filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_TRACER)

        refute filter.allows?(default_destination, AttributeFilter::DST_TRANSACTION_EVENTS)
        refute filter.allows?(default_destination, AttributeFilter::DST_BROWSER_MONITORING)
      end
    end

    def test_capture_params_false_adds_exclude_rule_for_request_parameters
      with_config(:capture_params => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('request.parameters.muggle', AttributeFilter::DST_NONE)

        assert_destinations [], result
      end
    end

    def test_capture_params_true_allows_request_params_for_traces_and_errors
      with_config(:capture_params => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('request.parameters.muggle', AttributeFilter::DST_NONE)

        assert_destinations %w[transaction_tracer error_collector], result
      end
    end

    def test_resque_capture_params_false_adds_exclude_rule_for_request_parameters
      with_config(:'resque.capture_params' => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('job.resque.args.*', AttributeFilter::DST_NONE)

        assert_destinations [], result
      end
    end

    def test_resque_capture_params_true_allows_request_params_for_traces_and_errors
      with_config(:'resque.capture_params' => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('job.resque.args.*', AttributeFilter::DST_NONE)

        assert_destinations %w[transaction_tracer error_collector], result
      end
    end

    def test_sidekiq_capture_params_false_adds_exclude_rule_for_request_parameters
      with_config(:'sidekiq.capture_params' => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('job.sidekiq.args.*', AttributeFilter::DST_NONE)

        assert_destinations [], result
      end
    end

    def test_sidekiq_capture_params_true_allows_request_params_for_traces_errors
      with_config(:'sidekiq.capture_params' => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('job.sidekiq.args.*', AttributeFilter::DST_NONE)

        assert_destinations %w[transaction_tracer error_collector], result
      end
    end

    def test_datastore_tracer_instance_reporting_disabled_adds_exclude_rule
      with_config(:'datastore_tracer.instance_reporting.enabled' => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('host', AttributeFilter::DST_NONE)

        assert_destinations [], result
      end
    end

    def test_datastore_tracer_instance_reporting_enabled_allows_instance_params
      with_config(:'datastore_tracer.instance_reporting.enabled' => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('host', AttributeFilter::DST_NONE)

        assert_destinations ['transaction_segments'], result
      end
    end

    def test_database_name_reporting_disabled_adds_exclude_rule
      with_config(:'datastore_tracer.database_name_reporting.enabled' => false) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('database_name', AttributeFilter::DST_NONE)

        assert_destinations [], result
      end
    end

    def test_database_name_reporting_enabled_allows_database_name
      with_config(:'datastore_tracer.database_name_reporting.enabled' => true) do
        filter = AttributeFilter.new(NewRelic::Agent.config)
        result = filter.apply('database_name', AttributeFilter::DST_NONE)

        assert_destinations ['transaction_segments'], result
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

    def test_span_global_include_exclude
      with_config(:'attributes.include' => ['request.headers.contentType'],
        :'attributes.exclude' => ['request.headers.*']) do
        filter = AttributeFilter.new(NewRelic::Agent.config)

        result = filter.apply('request.headers.contentType', AttributeFilter::DST_ALL)

        expected_destinations = %w[
          transaction_events
          transaction_tracer
          error_collector
          span_events
          transaction_segments
        ]

        assert_destinations expected_destinations, result
      end
    end

    def test_span_include_exclude
      with_config(:'span_events.attributes.include' => ['request.headers.contentType'],
        :'span_events.attributes.exclude' => ['request.headers.*']) do
        filter = AttributeFilter.new(NewRelic::Agent.config)

        result = filter.apply('request.headers.contentType', AttributeFilter::DST_SPAN_EVENTS)

        expected_destinations = ['span_events']

        assert_destinations expected_destinations, result
      end
    end

    def test_key_cache_global_include_exclude
      with_all_enabled do
        with_config(:'attributes.include' => ['request.headers.contentType'],
          :'attributes.exclude' => ['request.headers.*']) do
          filter = AttributeFilter.new(NewRelic::Agent.config)

          assert filter.allows_key?('request.headers.contentType', AttributeFilter::DST_ALL)
          refute filter.allows_key?('request.headers.accept', AttributeFilter::DST_ALL)
        end
      end
    end

    def test_key_cache_span_include_exclude
      with_config(:'span_events.attributes.include' => ['request.headers.contentType'],
        :'span_events.attributes.exclude' => ['request.headers.*']) do
        filter = AttributeFilter.new(NewRelic::Agent.config)

        assert filter.allows_key?('request.headers.contentType', AttributeFilter::DST_SPAN_EVENTS)
        refute filter.allows_key?('request.headers.accept', AttributeFilter::DST_SPAN_EVENTS)
      end
    end

    def test_excluding_url_attribute_excludes_all
      with_config(:'attributes.exclude' => ['request.uri']) do
        filter = AttributeFilter.new(NewRelic::Agent.config)

        refute filter.allows_key?('uri', AttributeFilter::DST_ALL)
        refute filter.allows_key?('url', AttributeFilter::DST_ALL)
        refute filter.allows_key?('request_uri', AttributeFilter::DST_ALL)
        refute filter.allows_key?('http.url', AttributeFilter::DST_ALL)
      end
    end

    def assert_destinations(expected, result)
      assert_equal to_bitfield(expected), result, "Expected #{expected}, got #{to_names(result)}"
    end

    def to_names(bitfield)
      names = []

      names << 'transaction_events' if (bitfield & AttributeFilter::DST_TRANSACTION_EVENTS) != 0
      names << 'transaction_tracer' if (bitfield & AttributeFilter::DST_TRANSACTION_TRACER) != 0
      names << 'error_collector' if (bitfield & AttributeFilter::DST_ERROR_COLLECTOR) != 0
      names << 'browser_monitoring' if (bitfield & AttributeFilter::DST_BROWSER_MONITORING) != 0
      names << 'span_events' if (bitfield & AttributeFilter::DST_SPAN_EVENTS) != 0
      names << 'transaction_segments' if (bitfield & AttributeFilter::DST_TRANSACTION_SEGMENTS) != 0

      names
    end

    def to_bitfield(destination_names)
      bitfield = AttributeFilter::DST_NONE

      destination_names.each do |name|
        case name
        when 'transaction_events' then bitfield |= AttributeFilter::DST_TRANSACTION_EVENTS
        when 'transaction_tracer' then bitfield |= AttributeFilter::DST_TRANSACTION_TRACER
        when 'error_collector' then bitfield |= AttributeFilter::DST_ERROR_COLLECTOR
        when 'browser_monitoring' then bitfield |= AttributeFilter::DST_BROWSER_MONITORING
        when 'span_events' then bitfield |= AttributeFilter::DST_SPAN_EVENTS
        when 'transaction_segments' then bitfield |= AttributeFilter::DST_TRANSACTION_SEGMENTS
        end
      end

      bitfield
    end

    def with_all_enabled
      with_config(
        :'transaction_tracer.attributes.enabled' => true,
        :'transaction_events.attributes.enabled' => true,
        :'error_collector.attributes.enabled' => true,
        :'browser_monitoring.attributes.enabled' => true,
        :'span_events.attributes.enabled' => true,
        :'transaction_segments.attributes.enabled' => true
      ) do
        yield
      end
    end
  end
end
