# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/server_source'

module NewRelic::Agent::Configuration
  class ServerSourceTest < Minitest::Test
    def setup
      config = {
        'agent_config' => {
          'slow_sql.enabled'                         => true,
          'transaction_tracer.transaction_threshold' => 'apdex_f',
          'transaction_tracer.record_sql'            => 'raw',
          'error_collector.enabled'                  => true
        },
        'apdex_t'                => 1.0,
        'collect_errors'         => false,
        'collect_traces'         => true,
        'web_transactions_apdex' => { 'Controller/some/txn' => 1.5 }
      }
      @source = ServerSource.new(config)
    end

    def test_should_set_apdex_t
      assert_equal 1.0, @source[:apdex_t]
    end

    def test_should_set_agent_config_values
      assert_equal 'raw', @source[:'transaction_tracer.record_sql']
    end

    def test_should_not_dot_the_agent_config_sub_hash
      assert_nil @source[:'agent_config.slow_sql.enabled']
    end

    def test_should_enable_tracer_as_configured
      assert @source[:'slow_sql.enabled']
    end

    def test_should_disable_tracer_as_configured
      assert !@source[:'error_collector.enabled']
    end

    def test_should_ignore_apdex_f_setting_for_transaction_threshold
      assert_equal nil, @source[:'transaction_tracer.transaction_threshold']
    end

    def test_should_not_dot_the_web_transactions_apdex_hash
      assert_equal 1.5, @source[:web_transactions_apdex]['Controller/some/txn']
    end

    def test_should_disable_gated_features_when_server_says_to
      rsp = {
        'collect_errors' => false,
        'collect_traces' => false,
        'collect_analytics_events' => false,
        'collect_custom_events'    => false
      }
      existing_config = {
        :'error_collector.enabled'        => true,
        :'slow_sql.enabled'               => true,
        :'transaction_tracer.enabled'     => true,
        :'analytics_events.enabled'       => true,
        :'custom_insights_events.enabled' => true
      }
      @source = ServerSource.new(rsp, existing_config)
      refute @source[:'error_collector.enabled']
      refute @source[:'slow_sql.enabled']
      refute @source[:'transaction_tracer.enabled']
      refute @source[:'analytics_events.enabled']
      refute @source[:'custom_insights_events.enabled']
    end

    def test_should_enable_gated_features_when_server_says_to
      rsp = {
        'collect_errors' => true,
        'collect_traces' => true,
        'collect_analytics_events' => true,
        'collect_custom_events'    => true
      }
      existing_config = {
        :'error_collector.enabled'        => true,
        :'slow_sql.enabled'               => true,
        :'transaction_tracer.enabled'     => true,
        :'analytics_events.enabled'       => true,
        :'custom_insights_events.enabled' => true
      }
      @source = ServerSource.new(rsp, existing_config)
      assert @source[:'error_collector.enabled']
      assert @source[:'slow_sql.enabled']
      assert @source[:'transaction_tracer.enabled']
      assert @source[:'analytics_events.enabled']
      assert @source[:'custom_insights_events.enabled']
    end

    def test_should_allow_manual_disable_of_gated_features
      rsp = {
        'collect_errors' => true,
        'collect_traces' => true,
        'collect_analytics_events' => true
      }
      existing_config = {
        :'error_collector.enabled'    => false,
        :'slow_sql.enabled'           => false,
        :'transaction_tracer.enabled' => false,
        :'analytics_events.enabled'   => false
      }
      @source = ServerSource.new(rsp, existing_config)
      assert !@source[:'error_collector.enabled']
      assert !@source[:'slow_sql.enabled']
      assert !@source[:'transaction_tracer.enabled']
      assert !@source[:'analytics_events.enabled']
    end

    def test_should_enable_gated_features_when_server_says_yes_and_existing_says_no
      rsp = {
        'collect_errors' => true,
        'collect_traces' => true,
        'collect_analytics_events' => true,
        'collect_custom_events'    => true,
        'agent_config' => {
          'transaction_tracer.enabled'     => true,
          'slow_sql.enabled'               => true,
          'error_collector.enabled'        => true,
          'analytics_events.enabled'       => true,
          'custom_insights_events.enabled' => true
        }
      }
      existing_config = {
        :'error_collector.enabled'        => false,
        :'slow_sql.enabled'               => false,
        :'transaction_tracer.enabled'     => false,
        :'analytics_events.enabled'       => false,
        :'custom_insights_events.enabled' => false
      }
      @source = ServerSource.new(rsp, existing_config)
      assert @source[:'error_collector.enabled']
      assert @source[:'slow_sql.enabled']
      assert @source[:'transaction_tracer.enabled']
      assert @source[:'analytics_events.enabled']
    end

    def test_should_not_gate_when_gating_keys_absent
      rsp = {
        'agent_config' => {
          'transaction_tracer.enabled'     => true,
          'slow_sql.enabled'               => true,
          'error_collector.enabled'        => true,
          'analytics_events.enabled'       => true,
          'custom_insights_events.enabled' => true
        }
      }
      @source = ServerSource.new(rsp, {})
      assert @source[:'error_collector.enabled']
      assert @source[:'slow_sql.enabled']
      assert @source[:'transaction_tracer.enabled']
      assert @source[:'analytics_events.enabled']
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
