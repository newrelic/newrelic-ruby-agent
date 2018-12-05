# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction_time_aggregator'

class NewRelic::Agent::TransctionTimeAggregatorTest < Minitest::Test
  def setup
    nr_freeze_time
    NewRelic::Agent.agent.stats_engine.clear_stats
  end

  def test_all_transactions_inside_harvest
    # Three ten-second transactions that lie entirely within the harvest:
    # 1-11s, 12-22s, 23-33s
    3.times do
      advance_time 1
      NewRelic::Agent::TransactionTimeAggregator.transaction_start
      advance_time 10
      NewRelic::Agent::TransactionTimeAggregator.transaction_stop Thread.current.object_id
    end

    # Simulate a 60-second harvest time
    advance_time 27

    busy_fraction = NewRelic::Agent::TransactionTimeAggregator.harvest!
    assert_equal 0.5, busy_fraction
  end

  def test_transaction_split_across_harvest
    thread_id = Thread.current.object_id

    # First transaction lies entirely within the harvest:
    # 1-11s
    advance_time 1
    NewRelic::Agent::TransactionTimeAggregator.transaction_start
    advance_time 10
    NewRelic::Agent::TransactionTimeAggregator.transaction_stop thread_id

    # Second transaction is split evenly across the harvest boundary:
    # 55-60s in the first harvest...
    advance_time 44
    NewRelic::Agent::TransactionTimeAggregator.transaction_start
    advance_time 5
    busy_fraction = NewRelic::Agent::TransactionTimeAggregator.harvest!
    assert_equal 0.25, busy_fraction

    # ...and 0-5s in the second harvest:
    advance_time 5
    NewRelic::Agent::TransactionTimeAggregator.transaction_stop thread_id
    advance_time 55

    busy_fraction = NewRelic::Agent::TransactionTimeAggregator.harvest!
    assert_equal 1.0 / 12.0, busy_fraction
  end

  def test_multithreading
    t0 = Time.now

    worker = Thread.new do
      ::NewRelic::Agent::TransactionTimeAggregator.transaction_start t0 + 27
      ::NewRelic::Agent::TransactionTimeAggregator.transaction_stop t0 + 47, Thread.current.object_id
    end

    # main thread:
    ::NewRelic::Agent::TransactionTimeAggregator.transaction_start t0 + 15
    ::NewRelic::Agent::TransactionTimeAggregator.transaction_stop t0 + 35, Thread.current.object_id

    worker.join

    busy_fraction = ::NewRelic::Agent::TransactionTimeAggregator.harvest! t0 + 60
    assert_equal 1.0 / 3.0, busy_fraction
  end

  def test_transactions_across_threads
    t0 = Time.now

    # main thread:
    ::NewRelic::Agent::TransactionTimeAggregator.transaction_start t0 + 15
    starting_thread_id = Thread.current.object_id

    worker = Thread.new do
      ::NewRelic::Agent::TransactionTimeAggregator.transaction_stop t0 + 35, starting_thread_id
    end

    worker.join

    busy_fraction = ::NewRelic::Agent::TransactionTimeAggregator.harvest! t0 + 60
    assert_equal 1.0 / 3.0, busy_fraction
  end

  def test_metrics

    NewRelic::Agent::TransactionTimeAggregator.transaction_start
    advance_time 12
    NewRelic::Agent::TransactionTimeAggregator.transaction_stop Thread.current.object_id
    advance_time 48

    NewRelic::Agent::TransactionTimeAggregator.harvest!

    spec = NewRelic::MetricSpec.new("Instance/Busy")
    stats = NewRelic::Agent.instance.stats_engine.to_h[spec]
    refute_nil stats

    assert_equal 1.0, stats.call_count
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

    t0 = Time.now
    workers = 100.times.map do
      Thread.new do
        ::NewRelic::Agent::TransactionTimeAggregator.transaction_start t0 + 15
        # thread dies before transaction completes
      end
    end

    workers.each { |w| w.join }

    ::NewRelic::Agent::TransactionTimeAggregator.harvest!
    assert_equal 0, stats.size, 'Aggregator did not cull dead threads'
  end
end
