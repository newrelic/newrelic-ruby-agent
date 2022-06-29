# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/configuration/event_harvest_config'

module NewRelic::Agent::Configuration
  class EventHarvestConfigTest < Minitest::Test
    def test_from_config
      config = NewRelic::Agent::Configuration::Manager.new
      config.add_config_for_testing(:'transaction_events.max_samples_stored' => 1000)
      config.add_config_for_testing(:'custom_insights_events.max_samples_stored' => 1000)
      config.add_config_for_testing(:'error_collector.max_event_samples_stored' => 1000)
      config.add_config_for_testing(:'span_events.max_event_samples_stored' => 2000)
      config.add_config_for_testing(:'application_logging.forwarding.max_samples_stored' => 2000)

      expected = {
        :harvest_limits => {
          :analytic_event_data => 1000,
          :custom_event_data => 1000,
          :error_event_data => 1000,
          :span_event_data => 2000,
          :log_event_data => 2000
        }
      }

      assert_equal(expected, EventHarvestConfig.from_config(config))
    end

    def test_to_config_hash
      connect_reply = {
        'event_harvest_config' => {
          'report_period_ms' => 5000,
          'harvest_limits' => {
            'analytic_event_data' => 833,
            'custom_event_data' => 83,
            'error_event_data' => 8,
            'log_event_data' => 833
          }
        },
        'span_event_harvest_config' => {
          'harvest_limit' => 89,
          'report_period_ms' => 80000
        }

      }

      expected = {
        :'transaction_events.max_samples_stored' => 833,
        :'event_report_period.transaction_event_data' => 5,
        :'custom_insights_events.max_samples_stored' => 83,
        :'event_report_period.custom_event_data' => 5,
        :'error_collector.max_event_samples_stored' => 8,
        :'event_report_period.error_event_data' => 5,
        :'span_events.max_samples_stored' => 89,
        :'event_report_period.span_event_data' => 80000,
        :event_report_period => 5,
        :'application_logging.forwarding.max_samples_stored' => 833,
        :'event_report_period.log_event_data' => 5
      }
      assert_equal expected, EventHarvestConfig.to_config_hash(connect_reply)
    end

    def test_to_config_hash_with_omitted_event_type
      connect_reply = {
        'event_harvest_config' => {
          'report_period_ms' => 5000,
          'harvest_limits' => {
            'analytic_event_data' => 833,
            'custom_event_data' => 83,
            'error_event_data' => 8,
            'log_event_data' => 833
          }
        }
      }

      expected = {
        :'transaction_events.max_samples_stored' => 833,
        :'event_report_period.transaction_event_data' => 5,
        :'custom_insights_events.max_samples_stored' => 83,
        :'event_report_period.custom_event_data' => 5,
        :'error_collector.max_event_samples_stored' => 8,
        :'event_report_period.error_event_data' => 5,
        :event_report_period => 5,
        :'application_logging.forwarding.max_samples_stored' => 833,
        :'event_report_period.log_event_data' => 5
      }
      assert_equal expected, EventHarvestConfig.to_config_hash(connect_reply)
    end

    def test_to_config_hash_with_zero_response_for_log_event_data
      connect_reply = {
        'event_harvest_config' => {
          'report_period_ms' => 5000,
          'harvest_limits' => {
            'log_event_data' => 0
          }
        }
      }

      expected = {
        :'application_logging.forwarding.max_samples_stored' => 0,
        :'event_report_period.log_event_data' => 5,
        :event_report_period => 5
      }
      assert_equal expected, EventHarvestConfig.to_config_hash(connect_reply)
    end
  end
end
