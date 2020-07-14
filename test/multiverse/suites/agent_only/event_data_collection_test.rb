# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'newrelic_rpm'

class EventDataCollectionTest < Minitest::Test
  include MultiverseHelpers

  def test_sends_all_event_capacities_on_connect
    expected = {
      'harvest_limits' => {
        "analytic_event_data" => 1200,
        "custom_event_data" => 1000,
        "error_event_data" => 100,
        "span_event_data" => 1000
      }
    }

    setup_agent

    assert_equal expected, single_connect_posted['event_harvest_config']
  end

  def test_sets_event_report_period_on_connect_repsonse
    connect_response = {
      "agent_run_id" => 1,
      "event_harvest_config" => {
        "report_period_ms" => 5000,
        "harvest_limits" => {
          "analytic_event_data" => 1200,
          "custom_event_data" => 1000,
          "error_event_data" => 100,
          "span_event_data" => 1000
        }
      }
    }

    setup_agent
    $collector.stub('connect', connect_response)
    trigger_agent_reconnect

    assert_equal 5, NewRelic::Agent.config[:event_report_period]
  end

  def test_resets_event_report_period_on_reconnect
    connect_response = {
      "agent_run_id" => 1,
      "event_harvest_config" => {
        "report_period_ms" => 5000,
        "harvest_limits" => {
          "analytic_event_data" => 1200,
          "custom_event_data" => 1000,
          "error_event_data" => 100,
          "span_event_data" => 1000
        }
      }
    }

    setup_agent
    $collector.stub('connect', connect_response)
    trigger_agent_reconnect

    assert_equal 5, NewRelic::Agent.config[:event_report_period]

    connect_response['event_harvest_config']['report_period_ms'] = 1000000
    $collector.stub('connect', connect_response)
    trigger_agent_reconnect

    assert_equal 1000, NewRelic::Agent.config[:event_report_period]
  end
end
