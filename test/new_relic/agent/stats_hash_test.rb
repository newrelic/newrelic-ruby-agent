require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','test_helper'))

class NewRelic::Agent::StatsHashTest < Test::Unit::TestCase
  def setup
    @hash = NewRelic::Agent::StatsHash.new
  end

  def test_creates_default_entries
    stats = @hash['a/b/c/d']
    assert_kind_of(NewRelic::Stats, stats)
  end

  def test_record_accpets_metric_name_and_records_unscoped_metric
    spec = NewRelic::MetricSpec.new('foo/bar')
    stats = @hash[spec]
    stats.expects(:record_data_point).with(42)
    @hash.record('foo/bar', 42)
  end

  def test_record_accepts_scope_option
    spec = NewRelic::MetricSpec.new('foo/bar', 'scope')
    stats = @hash[spec]
    stats.expects(:record_data_point).with(42)
    @hash.record('foo/bar', 42, :scope => 'scope')
  end

  def test_record_accepts_metric_spec_instead_of_name
    scoped_spec = NewRelic::MetricSpec.new('baz', 'scope')
    unscoped_spec = NewRelic::MetricSpec.new('baz')
    scoped_stats = @hash[scoped_spec]
    unscoped_stats = @hash[unscoped_spec]

    scoped_stats.expects(:record_data_point).with(42)
    unscoped_stats.expects(:record_data_point).with(43)

    @hash.record(scoped_spec, 42)
    @hash.record(unscoped_spec, 43)
  end

  def test_accepts_block_and_yields_stats
    spec = NewRelic::MetricSpec.new('foo/bar')
    @hash.record('foo/bar') do |stats|
      stats.record_data_point(42)
    end
    assert_equal(1, @hash[spec].call_count)
  end

  def test_accepts_exclusive_option_for_record_data_point
    spec = NewRelic::MetricSpec.new('foo/bar')
    stats = @hash[spec]
    stats.expects(:record_data_point).with(42, 32)
    @hash.record('foo/bar', 42, :exclusive => 32)
  end

  def test_merge_merges
    hash1 = NewRelic::Agent::StatsHash.new
    hash1.record('foo', 1)
    hash1.record('bar', 2)
    hash1.record('baz', 3, :scope => 's')

    hash2 = NewRelic::Agent::StatsHash.new
    hash2.record('foo', 1)
    hash2.record('bar', 2)
    hash2.record('baz', 3) # no scope

    hash1.merge!(hash2)

    assert_equal(4, hash1.keys.size)
    assert_equal(2, hash1[NewRelic::MetricSpec.new('foo')].call_count)
    assert_equal(2, hash1[NewRelic::MetricSpec.new('bar')].call_count)
    assert_equal(1, hash1[NewRelic::MetricSpec.new('baz')].call_count)
    assert_equal(1, hash1[NewRelic::MetricSpec.new('baz', 's')].call_count)
  end

  def test_marshal_dump
    hash = NewRelic::Agent::StatsHash.new()
    hash.record('foo', 1)
    hash.record('bar', 2)
    copy = Marshal.load(Marshal.dump(hash))
    assert_equal(hash, copy)
  end
end
