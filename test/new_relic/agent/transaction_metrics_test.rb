# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction_metrics'

class TransactionMetricsTest < Minitest::Test
  def setup
    @metrics = NewRelic::Agent::TransactionMetrics.new
  end

  def test_record_scoped_and_unscoped_should_record_a_scoped_metric
    @metrics.record_scoped_and_unscoped('foo', 42, 12)
    assert_scoped_metrics(@metrics, ['foo'], {
      :call_count           => 1,
      :total_call_time      => 42,
      :total_exclusive_time => 12
    })
    assert_unscoped_metrics(@metrics, [])
  end

  def test_record_scoped_and_unscoped_should_take_multiple_metrics
    @metrics.record_scoped_and_unscoped(['foo', 'bar'], 42, 12)
    assert_scoped_metrics(@metrics, ['foo', 'bar'], {
      :call_count           => 1,
      :total_call_time      => 42,
      :total_exclusive_time => 12
    })
    assert_unscoped_metrics(@metrics, [])
  end

  def test_record_scoped_and_unscoped_should_take_a_block
    @metrics.record_scoped_and_unscoped('foo') do |stats|
      stats.call_count           = 3
      stats.total_call_time      = 2
      stats.total_exclusive_time = 1
    end
    assert_scoped_metrics(@metrics, ['foo'], {
      :call_count           => 3,
      :total_call_time      => 2,
      :total_exclusive_time => 1
    })
    assert_unscoped_metrics(@metrics, [])
  end

  def test_record_unscoped_should_record_an_unscoped_metric
    @metrics.record_unscoped('foo', 42, 12)
    assert_unscoped_metrics(@metrics, ['foo'], {
      :call_count           => 1,
      :total_call_time      => 42,
      :total_exclusive_time => 12
    })
    assert_scoped_metrics(@metrics, [])
  end

  def test_record_unscoped_should_take_multiple_metrics
    @metrics.record_unscoped(['foo', 'bar'], 42, 12)
    assert_unscoped_metrics(@metrics, ['foo', 'bar'], {
      :call_count           => 1,
      :total_call_time      => 42,
      :total_exclusive_time => 12
    })
    assert_scoped_metrics(@metrics, [])
  end

  def test_record_unscoped_should_take_a_block
    @metrics.record_unscoped('foo') do |stats|
      stats.call_count           = 3
      stats.total_call_time      = 2
      stats.total_exclusive_time = 1
    end
    assert_unscoped_metrics(@metrics, ['foo'], {
      :call_count           => 3,
      :total_call_time      => 2,
      :total_exclusive_time => 1
    })
    assert_scoped_metrics(@metrics, [])
  end

  def test_square_brackets_look_up_unscoped_metrics
    @metrics.record_unscoped('foo', 42, 12)
    @metrics.record_scoped_and_unscoped('foo', 2, 1)
    assert_equal(42, @metrics['foo'].total_call_time)
  end

  def test_has_key_checks_for_unscoped_metric_presence
    refute @metrics.has_key?('foo')
  end

  def assert_unscoped_metrics(txn_metrics, expected_metric_names, expected_attrs={})
    assert_scoped_or_unscoped_metrics(:unscoped, txn_metrics, expected_metric_names, expected_attrs)
  end

  def assert_scoped_metrics(txn_metrics, expected_metric_names, expected_attrs={})
    assert_scoped_or_unscoped_metrics(:scoped, txn_metrics, expected_metric_names, expected_attrs)
  end

  def assert_scoped_or_unscoped_metrics(type, txn_metrics, expected_metric_names, expected_attrs)
    names     = []
    all_stats = []

    txn_metrics.send("each_#{type}") do |name, stats|
      names     << name
      all_stats << stats
    end

    assert_equal(expected_metric_names.sort, names.sort)
    names.zip(all_stats).each do |(name, stats)|
      assert_stats_has_values(stats, name, expected_attrs)
    end
  end
end
