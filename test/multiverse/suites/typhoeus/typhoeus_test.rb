# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'typhoeus'
require 'newrelic_rpm'
require 'fake_collector'
require 'test/unit'

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

class TyphoeusTest < Test::Unit::TestCase
  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run

    NewRelic::Agent.manual_start(
      :"cross_application_tracer.enabled" => false,
      :cross_process_id                   => '269975#22824',
      :encoding_key                       => 'gringletoes',
      :trusted_account_ids                => [269975]
    )

    NewRelic::Agent.instance.reset_stats

    NewRelic::Agent.instance.events.clear
    NewRelic::Agent.instance.cross_app_monitor.register_event_listeners
    NewRelic::Agent.instance.events.notify(:finished_configuring)
  end

  def test_basic_metrics
    response = get_response

    assert_equal 200, response.code
    assert_equal NewRelic::FakeCollector::STATUS_MESSAGE, response.body

    assert_metrics_recorded [
      "External/all",
      "External/allOther",
      "External/localhost/all",
      "External/localhost/Typhoeus/GET"]
  end

  def test_transaction_segment
    in_transaction('test') do
      get_response

      segment = find_last_transaction_segment
      assert_equal "External/localhost/Typhoeus/GET", segment.metric_name
    end
  end

  def test_cross_app
    with_config(:"cross_application_tracer.enabled" => true) do
      response = get_response
      assert_metrics_recorded [
        "ExternalTransaction/localhost/269975#22824/test"]
    end
  end

  def get_response
    Typhoeus.get("http://localhost:#{$collector.determine_port}/status")
  end

end

