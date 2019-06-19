# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/event_harvest_config'

class NewRelic::Agent::Configuration::EventHarvestConfigTest < Minitest::Test

  def test_from_config
    config = NewRelic::Agent::Configuration::Manager.new
    config.add_config_for_testing(:'analytics_events.max_samples_stored' => 1000)
    config.add_config_for_testing(:'custom_insights_events.max_samples_stored' => 1000)
    config.add_config_for_testing(:'error_collector.max_event_samples_stored' => 1000)

    expected = {
      :harvest_limits => {
        :analytic_event_data => 1000,
        :custom_event_data => 1000,
        :error_event_data => 1000
      }
    }

    assert_equal(expected, EventHarvestConfig.from_config(config))
  end

  def test_to_config_hash
    connect_reply = {
      'event_harvest_config' => {
        'report_period_ms' => 5000,
        'harvest_limits'   => {
          'analytic_event_data' => 833,
          'custom_event_data'   => 83,
          'error_event_data'    => 8
        }
      }
    }

    expected = {
      :'analytics_events.max_samples_stored' => 833,
      :'custom_insights_events.max_samples_stored' => 83,
      :'error_collector.max_event_samples_stored' => 8,
      :event_report_period => 5
    }
    assert_equal expected, EventHarvestConfig.to_config_hash(connect_reply)
  end
end