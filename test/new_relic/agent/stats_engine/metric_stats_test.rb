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
    @engine.harvest_timeslice_data({})
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

    harvested = @engine.harvest_timeslice_data({})

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

  def test_harvest_timeslice_data_applies_metric_rename_rules
    rule = NewRelic::Agent::RulesEngine::Rule.new(
      'match_expression' => '[0-9]+',
      'replacement'      => '*',
      'replace_all'      => true
    )
    rules_engine = NewRelic::Agent::RulesEngine.new([rule])

    @engine.get_stats_no_scope('Custom/foo/1/bar/22').record_data_point(1)
    @engine.get_stats_no_scope('Custom/foo/3/bar/44').record_data_point(1)
    @engine.get_stats_no_scope('Custom/foo/5/bar/66').record_data_point(1)

    harvested = @engine.harvest_timeslice_data({}, rules_engine)

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

    harvest = @engine.harvest_timeslice_data({})

    s = @engine.get_stats "a"
    assert_equal 0, s.call_count
    s.trace_call 2
    assert_equal 1, s.call_count

    # this call should merge the contents of the previous harvest,
    # so the stats for metric "a" should have 2 data points
    harvest = @engine.harvest_timeslice_data(harvest)
    stats = harvest.fetch(NewRelic::MetricSpec.new("a"))
    assert_equal 2, stats.call_count
    assert_equal 3, stats.total_call_time
  end

  def test_merge_merges
    @engine.get_stats("foo").record_data_point(1)

    other_stats_hash = NewRelic::Agent::StatsHash.new()
    other_stats_hash.record('foo', 1)
    other_stats_hash.record('bar', 1)

    @engine.merge!(other_stats_hash)

    foo_stats = @engine.get_stats('foo')
    bar_stats = @engine.get_stats('bar')
    assert_equal(2, foo_stats.call_count)
    assert_equal(1, bar_stats.call_count)
  end
end
