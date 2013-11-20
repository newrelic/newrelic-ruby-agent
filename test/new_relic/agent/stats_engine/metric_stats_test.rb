# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::MetricStatsTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent.manual_start
    @engine = NewRelic::Agent.instance.stats_engine
  rescue => e
    puts e
    puts e.backtrace.join("\n")
  end

  def teardown
    @engine.harvest
    super
  end

  def test_get_no_scope
    s1 = @engine.get_stats "a"
    s2 = @engine.get_stats "a"
    s3 = @engine.get_stats "b"

    assert_not_nil s1
    assert_not_nil s2
    assert_not_nil s3

    assert s1 == s2
    assert_not_same(s1, s3)
  end

  def test_harvest
    @engine.clear_stats
    s1 = @engine.get_stats "a"
    s2 = @engine.get_stats "c"

    s1.trace_call 10
    s2.trace_call 1
    s2.trace_call 3

    assert_equal 1, @engine.get_stats("a").call_count
    assert_equal 10, @engine.get_stats("a").total_call_time

    assert_equal 2, @engine.get_stats("c").call_count
    assert_equal 4, @engine.get_stats("c").total_call_time

    harvested = @engine.harvest

    # after harvest, all the metrics should be reset
    assert_equal 0, @engine.get_stats("a").call_count
    assert_equal 0, @engine.get_stats("a").total_call_time
    assert_equal 0, @engine.get_stats("c").call_count
    assert_equal 0, @engine.get_stats("c").total_call_time

    spec_a = NewRelic::MetricSpec.new('a')
    assert(harvested.has_key?(spec_a))
    assert_equal(1, harvested[spec_a].call_count)
    assert_equal(10, harvested[spec_a].total_call_time)
  end

  def test_harvest_applies_metric_rename_rules
    rule = NewRelic::Agent::RulesEngine::Rule.new(
      'match_expression' => '[0-9]+',
      'replacement'      => '*',
      'replace_all'      => true
    )
    rules_engine = NewRelic::Agent::RulesEngine.new([rule])

    @engine.metric_rules = rules_engine
    @engine.get_stats_no_scope('Custom/foo/1/bar/22').record_data_point(1)
    @engine.get_stats_no_scope('Custom/foo/3/bar/44').record_data_point(1)
    @engine.get_stats_no_scope('Custom/foo/5/bar/66').record_data_point(1)

    harvested = @engine.harvest

    assert !harvested.has_key?(NewRelic::MetricSpec.new('Custom/foo/1/bar/22'))
    assert !harvested.has_key?(NewRelic::MetricSpec.new('Custom/foo/3/bar/44'))
    assert !harvested.has_key?(NewRelic::MetricSpec.new('Custom/foo/5/bar/66'))
    merged = harvested[NewRelic::MetricSpec.new('Custom/foo/*/bar/*')]
    assert_equal(3, merged.call_count)
  end

  def test_harvest_with_merge
    s = @engine.get_stats "a"
    s.trace_call 1
    assert_equal 1, @engine.get_stats("a").call_count

    harvest = @engine.harvest

    s = @engine.get_stats "a"
    assert_equal 0, s.call_count
    s.trace_call 2
    assert_equal 1, s.call_count

    # this should merge the contents of the previous harvest,
    # so the stats for metric "a" should have 2 data points
    @engine.merge!(harvest)
    harvest = @engine.harvest
    stats = harvest.fetch(NewRelic::MetricSpec.new("a"))
    assert_equal 2, stats.call_count
    assert_equal 3, stats.total_call_time
  end

  def test_merge_merges
    @engine.get_stats("foo").record_data_point(1)

    other_stats_hash = NewRelic::Agent::StatsHash.new()
    other_stats_hash.record(NewRelic::MetricSpec.new('foo'), 1)
    other_stats_hash.record(NewRelic::MetricSpec.new('bar'), 1)

    @engine.merge!(other_stats_hash)

    foo_stats = @engine.get_stats('foo')
    bar_stats = @engine.get_stats('bar')
    assert_equal(2, foo_stats.call_count)
    assert_equal(1, bar_stats.call_count)
  end

  def test_harvest_adds_harvested_at_time
    t0 = freeze_time
    result = @engine.harvest
    assert_equal(t0, result.harvested_at)
  end

  def test_record_metrics_unscoped_metrics_only_by_default
    in_transaction('scopey') do
      @engine.record_metrics('foo', 42)
    end
    assert_metrics_recorded('foo' => { :call_count => 1, :total_call_time => 42 })
    assert_metrics_not_recorded([['foo', 'scopey']])
  end

  def test_record_metrics_records_to_scoped_metric_if_requested
    in_transaction('scopey') do
      @engine.record_metrics('foo', 42, :scoped => true)
    end
    unscoped_stats = @engine.get_stats('foo', false)
    scoped_stats = @engine.get_stats('foo', true, true, 'scopey')
    assert_equal(1, unscoped_stats.call_count, 'missing unscoped metric')
    assert_equal(1, scoped_stats.call_count, 'missing scoped metric')
  end

  def test_record_metrics_elides_scoped_metric_if_not_in_transaction
    @engine.clear_stats
    @engine.record_metrics('foo', 42, :scoped => true)
    unscoped_stats = @engine.get_stats('foo', false)
    assert_equal(1, unscoped_stats.call_count)
    assert_equal(1, @engine.metrics.size)
  end

  def test_record_metrics_accepts_block
    @engine.record_metrics('foo') do |stats|
      stats.call_count = 999
    end
    stats = @engine.get_stats_no_scope('foo')
    assert_equal(999, stats.call_count)
  end

  def test_record_metrics_is_thread_safe
    threads = []
    nthreads = 25
    iterations = 100
    nthreads.times do |tid|
      threads << Thread.new do
        iterations.times do
          @engine.record_metrics('m1', 1)
          @engine.record_metrics('m2', 1)
        end
      end
    end
    threads.each { |t| t.join }

    stats_m1 = @engine.get_stats_no_scope('m1')
    stats_m2 = @engine.get_stats_no_scope('m2')
    assert_equal(nthreads * iterations, stats_m1.call_count)
    assert_equal(nthreads * iterations, stats_m2.call_count)
  end

  def test_record_metrics_internal_writes_to_global_stats_hash_if_no_txn
    specs = [
      NewRelic::MetricSpec.new('foo'),
      NewRelic::MetricSpec.new('foo', 'scope')
    ]

    2.times { @engine.record_metrics_internal(specs, 10, 5) }

    expected = { :call_count => 2, :total_call_time => 20, :total_exclusive_time => 10 }
    assert_metrics_recorded('foo' => expected, ['foo', 'scope'] => expected)
  end

  def test_record_metrics_internal_writes_to_transaction_stats_hash_if_txn
    specs = [
      NewRelic::MetricSpec.new('foo'),
      NewRelic::MetricSpec.new('foo', 'scope')
    ]

    in_transaction do
      2.times { @engine.record_metrics_internal(specs, 10, 5) }
      # still in the txn, so metrics should not be visible in the global stats
      # hash yet
      assert_metrics_not_recorded(['foo', ['foo, scope']])
    end

    expected = { :call_count => 2, :total_call_time => 20, :total_exclusive_time => 10 }
    assert_metrics_recorded('foo' => expected, ['foo', 'scope'] => expected)
  end

  def test_transaction_stats_are_tracked_separately
    in_transaction do
      @engine.record_metrics('foo', 1)
      assert_nil @engine.lookup_stats('foo')
    end

    assert_equal 1, @engine.lookup_stats('foo').call_count
  end

  def test_record_supportability_metric_timed_records_duration_of_block
    freeze_time
    2.times do
      @engine.record_supportability_metric_timed('foo/bar') { advance_time(2.0) }
    end

    assert_metrics_recorded(['Supportability/foo/bar'] => {
      :call_count => 2,
      :total_call_time => 4.0
    })
  end

  def test_record_supportability_metric_timed_does_not_break_when_block_raises
    begin
      freeze_time
      @engine.record_supportability_metric_timed('foo/bar') do
        advance_time(2.0)
        1 / 0
      end
    rescue ZeroDivisionError
      nil
    end

    assert_metrics_recorded(['Supportability/foo/bar'] => {
      :call_count => 1,
      :total_call_time => 2.0
    })
  end

  def test_record_supportability_metric_count_records_counts_only
    @engine.record_supportability_metric_count('foo/bar', 1)
    @engine.record_supportability_metric_count('foo/bar', 42)
    assert_metrics_recorded(['Supportability/foo/bar'] => {
      :call_count => 42,
      :total_call_time => 0
    })
  end
end
