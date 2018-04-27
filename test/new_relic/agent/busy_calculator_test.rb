# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::BusyCalculatorTest < Minitest::Test
  attr_reader :now

  def setup
    @now = Time.now.to_f
    NewRelic::Agent::BusyCalculator.reset
    NewRelic::Agent.agent.stats_engine.clear_stats
  end

  def test_normal
    # start the timewindow 10 seconds ago
    # start a request at 10 seconds, 5 seconds long
    NewRelic::Agent::BusyCalculator.stubs(:harvest_start).returns(now - 10.0)
    NewRelic::Agent::BusyCalculator.dispatcher_start(now - 10.0)
    NewRelic::Agent::BusyCalculator.dispatcher_finish(now - 5.0)
    assert_equal 5, NewRelic::Agent::BusyCalculator.accumulator
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_instance_busy_metric_recorded call_count: 1, total_call_time: 0.50
  end

  def test_split
    # start the timewindow 10 seconds ago
    # start a request at 5 seconds, don't finish
    NewRelic::Agent::BusyCalculator.stubs(:harvest_start).returns(now - 10.0)
    NewRelic::Agent::BusyCalculator.dispatcher_start(now - 5.0)
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_instance_busy_metric_recorded call_count: 1, total_call_time: 0.50
  end

  def test_reentrancy
    # start the timewindow 10 seconds ago
    # start a request at 5 seconds, don't finish, but make two more
    # complete calls, which should be ignored.
    NewRelic::Agent::BusyCalculator.stubs(:harvest_start).returns(now - 10.0)
    NewRelic::Agent::BusyCalculator.dispatcher_start(now - 5.0)
    NewRelic::Agent::BusyCalculator.dispatcher_start(now - 4.5)
    NewRelic::Agent::BusyCalculator.dispatcher_start(now - 4.0)
    NewRelic::Agent::BusyCalculator.dispatcher_finish(now - 3.5)
    NewRelic::Agent::BusyCalculator.dispatcher_finish(now - 3.0)
    NewRelic::Agent::BusyCalculator.dispatcher_start(now - 2.0)
    NewRelic::Agent::BusyCalculator.dispatcher_finish(now - 1.0)
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_instance_busy_metric_recorded call_count: 1, total_call_time: 0.50
  end

  def test_concurrency
    # start the timewindow 10 seconds ago
    # start a request at 10 seconds, 5 seconds long
    NewRelic::Agent::BusyCalculator.stubs(:harvest_start).returns(now - 10.0)
    NewRelic::Agent::BusyCalculator.dispatcher_start(now - 8.0)
    worker = Thread.new do
      # Get busy for 6 - 3 seconds
      NewRelic::Agent::BusyCalculator.dispatcher_start(now - 6.0)
      NewRelic::Agent::BusyCalculator.dispatcher_start(now - 5.0)
      NewRelic::Agent::BusyCalculator.dispatcher_finish(now - 4.0)
      NewRelic::Agent::BusyCalculator.dispatcher_finish(now - 3.0)
    end
    # Get busy for 8 - 2 seconds
    NewRelic::Agent::BusyCalculator.dispatcher_finish(now - 2.0)
    worker.join

    NewRelic::Agent::BusyCalculator.stubs(:time_now).returns(now - 1.0)
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_instance_busy_metric_recorded call_count: 1, total_call_time: 1.0
  end

  def test_dont_ignore_zero_counts
    NewRelic::Agent::BusyCalculator.harvest_busy
    NewRelic::Agent::BusyCalculator.harvest_busy
    NewRelic::Agent::BusyCalculator.harvest_busy

    assert_instance_busy_metric_recorded :call_count => 3
  end

  def test_can_turn_off_recording
    with_config(:report_instance_busy => false) do
      NewRelic::Agent::BusyCalculator.harvest_busy
      assert_metrics_not_recorded 'Instance/Busy'
    end
  end

  def test_finishing_without_starting_doesnt_raise
    NewRelic::Agent::TransactionState.tl_clear
    NewRelic::Agent::BusyCalculator.dispatcher_finish
  end

  def assert_instance_busy_metric_recorded total_call_time: nil, call_count: 1
    spec = NewRelic::MetricSpec.new("Instance/Busy")
    stats = NewRelic::Agent.instance.stats_engine.to_h[spec]
    refute_nil stats
    assert_equal call_count, stats.call_count
    assert_in_delta total_call_time, stats.total_call_time, 0.01 if total_call_time
  end
end
