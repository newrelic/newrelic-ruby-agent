# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/configuration/server_source'

module NewRelic::Agent::Configuration
  class ServerSourceTest < Minitest::Test
    def setup
      NewRelic::Agent.instance.stats_engine.reset!
      @config = {
        'agent_config' => {
          'slow_sql.enabled' => true,
          'transaction_tracer.transaction_threshold' => 'apdex_f',
          'transaction_tracer.record_sql' => 'raw',
          'error_collector.enabled' => true
        },
        'event_harvest_config' => {
          'report_period_ms' => 5000,
          'harvest_limits' => {
            'analytic_event_data' => 833,
            'custom_event_data' => 833,
            'error_event_data' => 8,
            'log_event_data' => 833
          }
        },
        'span_event_harvest_config' => {
          'harvest_limit' => 89,
          'report_period_ms' => 80000
        },
        'apdex_t' => 1.0,
        'collect_errors' => false,
        'collect_traces' => true,
        'web_transactions_apdex' => {'Controller/some/txn' => 1.5},
        'trusted_account_key' => '555',
        'account_id' => '190',
        'primary_application_id' => '1441',
        'entity_guid' => 'MXxBUE18QVBQTElDQV',
        'sampling_target' => 20,
        'sampling_target_period_in_seconds' => 120,
        'max_payload_size_in_bytes' => 500
      }
      @source = ServerSource.new(@config)
    end

    def test_should_set_apdex_t
      assert_equal 1.0, @source[:apdex_t]
    end

    def test_should_set_agent_config_values
      assert_equal 'raw', @source[:'transaction_tracer.record_sql']
    end

    def test_should_set_trusted_account_key
      assert_equal '555', @source[:trusted_account_key]
    end

    def test_should_set_account_id
      assert_equal '190', @source[:account_id]
    end

    def test_should_set_primary_application_id
      assert_equal '1441', @source[:primary_application_id]
    end

    def test_should_set_entity_guid
      assert_equal 'MXxBUE18QVBQTElDQV', @source[:entity_guid]
    end

    def test_should_set_sampling_target
      assert_equal 20, @source[:sampling_target]
    end

    def test_should_set_sampling_target_in_seconds
      assert_equal 120, @source[:sampling_target_period_in_seconds]
    end

    def test_should_set_max_payload_size_in_bytes
      assert_equal 500, @source[:max_payload_size_in_bytes]
    end

    def test_should_not_dot_the_agent_config_sub_hash
      assert_nil @source[:'agent_config.slow_sql.enabled']
    end

    def test_should_enable_tracer_as_configured
      assert @source[:'slow_sql.enabled']
    end

    def test_should_disable_tracer_as_configured
      refute @source[:'error_collector.enabled']
    end

    def test_should_ignore_apdex_f_setting_for_transaction_threshold
      assert_nil @source[:'transaction_tracer.transaction_threshold']
    end

    def test_should_not_dot_the_web_transactions_apdex_hash
      assert_equal 1.5, @source[:web_transactions_apdex]['Controller/some/txn']
    end

    def test_should_set_analytics_events_max_samples
      assert_equal 833, @source[:'transaction_events.max_samples_stored']
      assert_metrics_recorded({"Supportability/EventHarvest/AnalyticEventData/HarvestLimit" => {total_call_time: 833}})
    end

    def test_should_set_custom_events_max_samples
      assert_equal 833, @source[:'custom_insights_events.max_samples_stored']
      assert_metrics_recorded({"Supportability/EventHarvest/CustomEventData/HarvestLimit" => {total_call_time: 833}})
    end

    def test_should_set_error_events_max_samples
      assert_equal 8, @source[:'error_collector.max_event_samples_stored']
      assert_metrics_recorded({"Supportability/EventHarvest/ErrorEventData/HarvestLimit" => {total_call_time: 8}})
    end

    def test_should_set_log_events_max_samples
      assert_equal 833, @source[:'application_logging.forwarding.max_samples_stored']
      assert_metrics_recorded({"Supportability/EventHarvest/LogEventData/HarvestLimit" => {total_call_time: 833}})
    end

    def test_should_set_span_events_max_samples
      assert_equal 89, @source[:'span_events.max_samples_stored']
      assert_metrics_recorded({"Supportability/SpanEvent/Limit" => {total_call_time: 89}})
    end

    def test_should_set_event_report_period
      assert_equal 5, @source[:'event_report_period']
      assert_metrics_recorded({"Supportability/EventHarvest/ReportPeriod" => {total_call_time: 5}})
    end

    def test_should_set_span_event_report_period
      assert_equal 80000, @source[:'event_report_period.span_event_data']
      assert_metrics_recorded({"Supportability/SpanEvent/ReportPeriod" => {total_call_time: 80000}})
    end

    def test_should_correctly_handle_missing_event_type_from_event_harvest_config
      @config.delete('span_event_harvest_config')
      @source = ServerSource.new(@config)

      # Span events should fall back to default source
      refute @source[:'span_events.max_samples_stored'], "Expected span events to be excluded from server source"

      # The event report period and limits for other event types should still be in server source
      assert_equal 5, @source[:'event_report_period']
      assert_equal 833, @source[:'transaction_events.max_samples_stored']
      assert_equal 833, @source[:'custom_insights_events.max_samples_stored']
      assert_equal 8, @source[:'error_collector.max_event_samples_stored']
    end

    def test_should_disable_gated_features_when_server_says_to
      rsp = {
        'collect_errors' => false,
        'collect_traces' => false,
        'collect_analytics_events' => false,
        'collect_custom_events' => false
      }
      existing_config = {
        :'error_collector.enabled' => true,
        :'slow_sql.enabled' => true,
        :'transaction_tracer.enabled' => true,
        :'transaction_events.enabled' => true,
        :'custom_insights_events.enabled' => true
      }
      @source = ServerSource.new(rsp, existing_config)
      refute @source[:'error_collector.enabled']
      refute @source[:'slow_sql.enabled']
      refute @source[:'transaction_tracer.enabled']
      refute @source[:'transaction_events.enabled']
      refute @source[:'custom_insights_events.enabled']
    end

    def test_should_enable_gated_features_when_server_says_to
      rsp = {
        'collect_errors' => true,
        'collect_traces' => true,
        'collect_analytics_events' => true,
        'collect_custom_events' => true
      }
      existing_config = {
        :'error_collector.enabled' => true,
        :'slow_sql.enabled' => true,
        :'transaction_tracer.enabled' => true,
        :'transaction_events.enabled' => true,
        :'custom_insights_events.enabled' => true
      }
      @source = ServerSource.new(rsp, existing_config)
      assert @source[:'error_collector.enabled']
      assert @source[:'slow_sql.enabled']
      assert @source[:'transaction_tracer.enabled']
      assert @source[:'transaction_events.enabled']
      assert @source[:'custom_insights_events.enabled']
    end

    def test_should_allow_manual_disable_of_gated_features
      rsp = {
        'collect_errors' => true,
        'collect_traces' => true,
        'collect_analytics_events' => true
      }
      existing_config = {
        :'error_collector.enabled' => false,
        :'slow_sql.enabled' => false,
        :'transaction_tracer.enabled' => false,
        :'transaction_events.enabled' => false
      }
      @source = ServerSource.new(rsp, existing_config)
      refute @source[:'error_collector.enabled']
      refute @source[:'slow_sql.enabled']
      refute @source[:'transaction_tracer.enabled']
      refute @source[:'transaction_events.enabled']
    end

    def test_should_enable_gated_features_when_server_says_yes_and_existing_says_no
      rsp = {
        'collect_errors' => true,
        'collect_traces' => true,
        'collect_analytics_events' => true,
        'collect_custom_events' => true,
        'agent_config' => {
          'transaction_tracer.enabled' => true,
          'slow_sql.enabled' => true,
          'error_collector.enabled' => true,
          'transaction_events.enabled' => true,
          'custom_insights_events.enabled' => true
        }
      }
      existing_config = {
        :'error_collector.enabled' => false,
        :'slow_sql.enabled' => false,
        :'transaction_tracer.enabled' => false,
        :'transaction_events.enabled' => false,
        :'custom_insights_events.enabled' => false
      }
      @source = ServerSource.new(rsp, existing_config)
      assert @source[:'error_collector.enabled']
      assert @source[:'slow_sql.enabled']
      assert @source[:'transaction_tracer.enabled']
      assert @source[:'transaction_events.enabled']
    end

    def test_should_not_gate_when_gating_keys_absent
      rsp = {
        'agent_config' => {
          'transaction_tracer.enabled' => true,
          'slow_sql.enabled' => true,
          'error_collector.enabled' => true,
          'transaction_events.enabled' => true,
          'custom_insights_events.enabled' => true
        }
      }
      @source = ServerSource.new(rsp, {})
      assert @source[:'error_collector.enabled']
      assert @source[:'slow_sql.enabled']
      assert @source[:'transaction_tracer.enabled']
      assert @source[:'transaction_events.enabled']
      assert @source[:'custom_insights_events.enabled']
    end

    def test_should_strip_non_ssc_keys
      rsp = {
        'agent_config' => {
          'attributes.include' => 'foo,bar',
          'slow_sql.explain_threshold' => 42
        }
      }

      source = ServerSource.new(rsp, {})
      refute_includes source.keys, :'attributes.include'
      assert_includes source.keys, :'slow_sql.explain_threshold'
    end

    def test_should_strip_unrecognized_keys_in_agent_config_hash
      rsp = {
        'agent_config' => {
          'platypus' => 'mammal'
        }
      }

      source = ServerSource.new(rsp, {})
      refute_includes source.keys, :platypus
    end

    def test_should_not_merge_in_keys_that_are_not_allowed_at_top_level
      rsp = {
        'slow_sql.explain_threshold' => 42
      }
      source = ServerSource.new(rsp, {})
      refute_includes source.keys, :'slow_sql.explain_threshold'
    end

    def test_all_top_level_keys_should_be_allowed_from_server
      ServerSource::TOP_LEVEL_KEYS.each do |key|
        assert DEFAULTS[key.to_sym], "Did not find entry in config DEFAULTS hash for to-level server config key #{key}"
        assert DEFAULTS[key.to_sym][:allowed_from_server], "Expected top-level server config key #{key} to be allowed from server"
      end
    end
  end
end
