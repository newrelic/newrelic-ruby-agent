# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/transaction_time_aggregator'

class NewRelic::Agent::TransactionTimeAggregatorTest < Minitest::Test
  def setup
    nr_freeze_process_time
    NewRelic::Agent.agent.stats_engine.clear_stats
  end

  def test_all_transactions_inside_harvest
    # Three ten-second transactions that lie entirely within the harvest:
    # 1-11s, 12-22s, 23-33s
    3.times do
      advance_process_time(1)
      NewRelic::Agent::TransactionTimeAggregator.transaction_start
      advance_process_time(10)
      NewRelic::Agent::TransactionTimeAggregator.transaction_stop
    end

    # Simulate a 60-second harvest time
    advance_process_time(27)

    busy_fraction = NewRelic::Agent::TransactionTimeAggregator.harvest!

    assert_in_delta(0.5, busy_fraction)
  end

  def test_transaction_split_across_harvest
    # First transaction lies entirely within the harvest:
    # 1-11s
    advance_process_time(1)
    NewRelic::Agent::TransactionTimeAggregator.transaction_start
    advance_process_time(10)
    NewRelic::Agent::TransactionTimeAggregator.transaction_stop

    # Second transaction is split evenly across the harvest boundary:
    # 55-60s in the first harvest...
    advance_process_time(44)
    NewRelic::Agent::TransactionTimeAggregator.transaction_start
    advance_process_time(5)
    busy_fraction = NewRelic::Agent::TransactionTimeAggregator.harvest!

    assert_in_delta(0.25, busy_fraction)

    # ...and 0-5s in the second harvest:
    advance_process_time(5)
    NewRelic::Agent::TransactionTimeAggregator.transaction_stop
    advance_process_time(55)

    busy_fraction = NewRelic::Agent::TransactionTimeAggregator.harvest!

    assert_equal 1.0 / 12.0, busy_fraction
  end

  def test_multithreading
    t0 = Process.clock_gettime(Process::CLOCK_REALTIME)

    worker = Thread.new do
      ::NewRelic::Agent::TransactionTimeAggregator.transaction_start(t0 + 27)
      ::NewRelic::Agent::TransactionTimeAggregator.transaction_stop(t0 + 47)
    end

    # main thread:
    ::NewRelic::Agent::TransactionTimeAggregator.transaction_start(t0 + 15)
    ::NewRelic::Agent::TransactionTimeAggregator.transaction_stop(t0 + 35)

    worker.join

    busy_fraction = ::NewRelic::Agent::TransactionTimeAggregator.harvest!(t0 + 60)

    assert_equal 1.0 / 3.0, busy_fraction
  end

  def test_transactions_across_threads
    t0 = Process.clock_gettime(Process::CLOCK_REALTIME)

    # main thread:
    ::NewRelic::Agent::TransactionTimeAggregator.transaction_start(t0 + 15)
    starting_thread_id = Thread.current.object_id

    worker = Thread.new do
      ::NewRelic::Agent::TransactionTimeAggregator.transaction_stop(t0 + 35, starting_thread_id)
    end

    worker.join

    busy_fraction = ::NewRelic::Agent::TransactionTimeAggregator.harvest!(t0 + 60)

    assert_equal 1.0 / 3.0, busy_fraction
  end

  def test_metrics
    NewRelic::Agent::TransactionTimeAggregator.transaction_start
    advance_process_time(12)
    NewRelic::Agent::TransactionTimeAggregator.transaction_stop
    advance_process_time(48)

    NewRelic::Agent::TransactionTimeAggregator.harvest!

    spec = NewRelic::MetricSpec.new("Instance/Busy")
    stats = NewRelic::Agent.instance.stats_engine.to_h[spec]

    refute_nil stats

    assert_in_delta(1.0, stats.call_count)
    assert_in_delta 0.2, stats.total_call_time, 0.000001
  end

  def test_disable_metrics
    with_config(report_instance_busy: false) do
      NewRelic::Agent::TransactionTimeAggregator.harvest!

      assert_metrics_not_recorded 'Instance/Busy'
    end
  end

  def test_culls_dead_threads
    stats = NewRelic::Agent::TransactionTimeAggregator.instance_variable_get(:@stats)

    t0 = Process.clock_gettime(Process::CLOCK_REALTIME)
    workers = Array.new(100) do
      Thread.new do
        ::NewRelic::Agent::TransactionTimeAggregator.transaction_start(t0 + 15)
        # thread dies before transaction completes
      end
    end

    workers.each { |w| w.join }

    ::NewRelic::Agent::TransactionTimeAggregator.harvest!

    assert_equal 0, stats.size, 'Aggregator did not cull dead threads'
  end
end
