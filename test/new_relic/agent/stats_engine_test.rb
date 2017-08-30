# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..', 'test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

class NewRelic::Agent::StatsEngineTest < Minitest::Test
  def setup
    NewRelic::Agent.manual_start
    @engine = NewRelic::Agent.instance.stats_engine
  rescue => e
    puts e
    puts e.backtrace.join("\n")
  end

  def teardown
    @engine.reset!
    NewRelic::Agent.shutdown
    super
  end

  # Helpers for DataContainerTests

  def create_container
    NewRelic::Agent::StatsEngine.new
  end

  def populate_container(engine, n)
    n.times do |i|
      engine.tl_record_unscoped_metrics("metric#{i}", i)
    end
  end

  include NewRelic::DataContainerTests


  def test_record_unscoped_metrics_records_to_transaction_stats_if_in_txn
    in_transaction do
      @engine.tl_record_unscoped_metrics(['a', 'b'], 20, 10)

      # txn is still active, so metrics should not be merged into global
      # stats hash yet
      assert_metrics_not_recorded(['a', 'b'])
    end

    expected = {
      :call_count           => 1,
      :total_call_time      => 20,
      :total_exclusive_time => 10
    }
    assert_metrics_recorded(
      'a' => expected,
      'b' => expected
    )
  end

  def test_record_unscoped_metrics_records_to_global_metrics_if_no_txn
    @engine.tl_record_unscoped_metrics(['a', 'b'], 20, 10)
    expected = {
      :call_count           => 1,
      :total_call_time      => 20,
      :total_exclusive_time => 10
    }
    assert_metrics_recorded(
      'a' => expected,
      'b' => expected
    )
  end

  def test_record_unscoped_metrics_takes_single_metric_name
    @engine.tl_record_unscoped_metrics('a', 20)
    assert_metrics_recorded(
      'a' => {
        :call_count           => 1,
        :total_call_time      => 20,
        :total_exclusive_time => 20
      }
    )
  end

  def test_record_unscoped_metrics_takes_block_in_txn
    in_transaction('txn') do
      @engine.tl_record_unscoped_metrics('a') do |stat|
        stat.total_call_time = 42
        stat.call_count = 99
      end
    end

    expected = { :total_call_time => 42, :call_count => 99 }
    assert_metrics_recorded('a' => expected)
  end

  def test_record_unscoped_metrics_takes_block_outside_txn
    @engine.tl_record_unscoped_metrics('a') do |stat|
      stat.total_call_time = 42
      stat.call_count = 99
    end

    expected = { :total_call_time => 42, :call_count => 99 }
    assert_metrics_recorded('a' => expected)
  end

  def test_record_unscoped_metrics_is_thread_safe
    threads = []
    nthreads = 25
    iterations = 100

    nthreads.times do |tid|
      threads << Thread.new do
        iterations.times do
          @engine.tl_record_unscoped_metrics('m1', 1)
          @engine.tl_record_unscoped_metrics('m2', 1)
        end
      end
    end
    threads.each { |t| t.join }

    assert_metrics_recorded(
      'm1' => { :call_count => nthreads * iterations },
      'm2' => { :call_count => nthreads * iterations }
    )
  end

  def test_record_scoped_and_unscoped_metrics_records_scoped_and_unscoped
    in_transaction('txn') do
      @engine.tl_record_scoped_and_unscoped_metrics('a', nil, 20, 10)
      assert_metrics_not_recorded('a')
    end

    expected = {
      :call_count           => 1,
      :total_call_time      => 20,
      :total_exclusive_time => 10
    }
    assert_metrics_recorded(
      'a'          => expected,
      ['a', 'txn'] => expected
    )
  end

  def test_record_scoped_and_unscoped_metrics_takes_block
    in_transaction('txn') do
      @engine.tl_record_scoped_and_unscoped_metrics('a', ['b']) do |stat|
        stat.total_call_time = 42
        stat.call_count = 99
      end
    end

    expected = { :total_call_time => 42, :call_count => 99 }
    assert_metrics_recorded(
      'a'          => expected,
      ['a', 'txn'] => expected,
      'b'          => expected
    )
  end

  def test_record_scoped_and_unscoped_metrics_records_multiple_unscoped_metrics
    in_transaction('txn') do
      @engine.tl_record_scoped_and_unscoped_metrics('a', ['b', 'c'], 20, 10)
      assert_metrics_not_recorded(['a', 'b', 'c'])
    end

    expected = {
      :call_count           => 1,
      :total_call_time      => 20,
      :total_exclusive_time => 10
    }
    assert_metrics_recorded(
      'a'          => expected,
      ['a', 'txn'] => expected,
      'b'          => expected,
      'c'          => expected
    )
    assert_metrics_not_recorded([
      ['b', 'txn'],
      ['c', 'txn']
    ])
  end

  def test_record_scoped_and_unscoped_metrics_is_thread_safe
    threads = []
    nthreads = 25
    iterations = 100

    nthreads.times do |tid|
      threads << Thread.new do
        iterations.times do
          in_transaction('txn') do
            @engine.tl_record_scoped_and_unscoped_metrics('m1', ['m3'], 1)
            @engine.tl_record_scoped_and_unscoped_metrics('m2', ['m4'], 1)
          end
        end
      end
    end
    threads.each { |t| t.join }

    expected = { :call_count => nthreads * iterations }
    assert_metrics_recorded(
      'm1'          => expected,
      'm2'          => expected,
      ['m1', 'txn'] => expected,
      ['m2', 'txn'] => expected,
      'm3'          => expected,
      'm4'          => expected
    )
  end

  def test_record_scoped_and_unscoped_metrics_records_unscoped_if_not_in_txn
    @engine.tl_record_scoped_and_unscoped_metrics('a', ['b'], 20, 10)

    expected = {
      :call_count           => 1,
      :total_call_time      => 20,
      :total_exclusive_time => 10
    }
    assert_metrics_recorded_exclusive(
      'a' => expected,
      'b' => expected,
      'Supportability/API/shutdown' => 1,
      'Supportability/API/manual_start' => 1
    )
  end

  def test_harvest
    @engine.clear_stats

    @engine.tl_record_unscoped_metrics "a", 10
    @engine.tl_record_unscoped_metrics "c", 1
    @engine.tl_record_unscoped_metrics "c", 3

    assert_metrics_recorded({
      "a" => {:call_count => 1, :total_call_time => 10},
      "c" => {:call_count => 2, :total_call_time => 4}
    })

    harvested = @engine.harvest!.to_h

    # after harvest, all the metrics should be reset
    refute_metrics_recorded %w(a c)

    spec_a = NewRelic::MetricSpec.new('a')

    assert(harvested.has_key?(spec_a))
    assert_equal(1, harvested[spec_a].call_count)
    assert_equal(10, harvested[spec_a].total_call_time)
  end

  def test_harvest_applies_metric_rename_rules
    rule = NewRelic::Agent::RulesEngine::ReplacementRule.new(
      'match_expression' => '[0-9]+',
      'replacement'      => '*',
      'replace_all'      => true
    )
    rules_engine = NewRelic::Agent::RulesEngine.new([rule])

    @engine.metric_rules = rules_engine
    @engine.tl_record_unscoped_metrics('Custom/foo/1/bar/22', 1)
    @engine.tl_record_unscoped_metrics('Custom/foo/3/bar/44', 1)
    @engine.tl_record_unscoped_metrics('Custom/foo/5/bar/66', 1)

    harvested = @engine.harvest!.to_h

    refute harvested.has_key?(NewRelic::MetricSpec.new('Custom/foo/1/bar/22'))
    refute harvested.has_key?(NewRelic::MetricSpec.new('Custom/foo/3/bar/44'))
    refute harvested.has_key?(NewRelic::MetricSpec.new('Custom/foo/5/bar/66'))
    merged = harvested[NewRelic::MetricSpec.new('Custom/foo/*/bar/*')]
    assert_equal(3, merged.call_count)
  end

  def test_apply_rules_to_metric_data_respects_ignore_rules
    rule = NewRelic::Agent::RulesEngine::ReplacementRule.new(
      'match_expression' => 'bar',
      'ignore'           => 'true'
    )
    rules_engine = NewRelic::Agent::RulesEngine.new([rule])

    stats_hash = NewRelic::Agent::StatsHash.new

    stats_hash.record(NewRelic::MetricSpec.new('foo'), 90210)
    stats_hash.record(NewRelic::MetricSpec.new('bar'), 90210)

    renamed = @engine.apply_rules_to_metric_data(rules_engine, stats_hash)

    assert_equal(1    , renamed.size)
    assert_equal('foo', renamed.to_h.keys.first.name)
  end

  def test_harvest_with_merge
    @engine.tl_record_unscoped_metrics "a", 1
    assert_metrics_recorded "a" => {:call_count => 1, :total_call_time => 1}

    harvest = @engine.harvest!

    assert_metrics_not_recorded "a"

    @engine.tl_record_unscoped_metrics "a", 2
    assert_metrics_recorded "a" => {:call_count => 1, :total_call_time => 2}

    # this should merge the contents of the previous harvest,
    # so the stats for metric "a" should have 2 data points
    @engine.merge!(harvest)
    harvest = @engine.harvest!
    stats = harvest[NewRelic::MetricSpec.new("a")]
    assert_equal 2, stats.call_count
    assert_equal 3, stats.total_call_time
  end

  def test_merge_merges
    @engine.tl_record_unscoped_metrics "foo", 1

    other_stats_hash = NewRelic::Agent::StatsHash.new()
    other_stats_hash.record(NewRelic::MetricSpec.new('foo'), 1)
    other_stats_hash.record(NewRelic::MetricSpec.new('bar'), 1)

    @engine.merge!(other_stats_hash)

    assert_metrics_recorded ({
      'foo' => {:call_count => 2},
      'bar' => {:call_count => 1}
    })
  end

  def test_harvest_adds_harvested_at_time
    t0 = freeze_time
    result = @engine.harvest!
    assert_equal(t0, result.harvested_at)
  end

  def test_record_unscoped_metrics_unscoped_metrics_only
    in_transaction('scopey') do
      @engine.tl_record_unscoped_metrics('foo', 42)
    end
    assert_metrics_recorded('foo' => { :call_count => 1, :total_call_time => 42 })
    assert_metrics_not_recorded([['foo', 'scopey']])
  end

  def test_record_supportability_metric_count_records_counts_only
    @engine.tl_record_supportability_metric_count('foo/bar',  1)
    @engine.tl_record_supportability_metric_count('foo/bar', 42)
    assert_metrics_recorded(['Supportability/foo/bar'] => {
      :call_count => 42,
      :total_call_time => 0
    })
  end
end
