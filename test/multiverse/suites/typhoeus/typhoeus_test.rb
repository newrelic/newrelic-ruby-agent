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

    NewRelic::Agent.instance.reset_stats
  end

  def test_basic_metrics
    response = Typhoeus.get("http://localhost:#{$collector.determine_port}/status")

    assert_equal 200, response.code
    assert_equal NewRelic::FakeCollector::STATUS_MESSAGE, response.body

    assert_metrics_recorded [
      "External/all",
      "External/localhost/all",
      "External/localhost/Typhoeus/GET"]
  end
end

