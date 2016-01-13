# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..','test_helper'))

class NewRelic::Agent::StatsHashTest < Minitest::Test
  def setup
    @hash = NewRelic::Agent::StatsHash.new
    reset_error_traces!
  end

  def test_creates_default_entries
    stats = @hash[NewRelic::MetricSpec.new('a/b/c/d')]
    assert_kind_of(NewRelic::Agent::Stats, stats)
  end

  def test_record_accpets_single_metric_spec
    spec = NewRelic::MetricSpec.new('foo/bar')
    stats = @hash[spec]
    stats.expects(:record_data_point).with(42, 42)
    @hash.record(spec, 42)
  end

  def test_record_accepts_multiple_metric_specs
    spec1 = NewRelic::MetricSpec.new('foo/bar', 'scope1')
    spec2 = NewRelic::MetricSpec.new('foo/bar', 'scope2')
    stats1 = @hash[spec1]
    stats2 = @hash[spec2]
    stats1.expects(:record_data_point).with(42, 42)
    stats2.expects(:record_data_point).with(42, 42)
    @hash.record([spec1, spec2], 42)
  end

  def test_record_accepts_single_metric_spec_with_block
    spec = NewRelic::MetricSpec.new('foo')
    stats = @hash[spec]
    stats.expects(:do_stuff)
    @hash.record(spec) do |s|
      s.do_stuff
    end
  end

  def test_record_accepts_multiple_metric_specs_with_block
    specs = [
      NewRelic::MetricSpec.new('foo'),
      NewRelic::MetricSpec.new('bar')
    ]
    stats = specs.map { |spec| @hash[spec] }
    stats.each { |stat| stat.expects(:do_stuff) }
    @hash.record(specs) do |s|
      s.do_stuff
    end
  end

  def test_record_accepts_stats_value
    spec = NewRelic::MetricSpec.new('foo')
    other_stats = NewRelic::Agent::Stats.new
    stats = @hash[spec]
    stats.expects(:merge!).with(other_stats)
    @hash.record(spec, other_stats)
  end

  def test_record_accepts_exclusive_time_with_numeric
    spec = NewRelic::MetricSpec.new('foo')
    stats = @hash[spec]
    stats.expects(:record_data_point).with(42, 10)
    @hash.record(spec, 42, 10)
  end

  def test_record_accepts_apdex_t_with_symbol
    spec = NewRelic::MetricSpec.new('foo')
    apdex_t = 99
    1.times { @hash.record(spec, :apdex_s, apdex_t) }
    2.times { @hash.record(spec, :apdex_t, apdex_t) }
    3.times { @hash.record(spec, :apdex_f, apdex_t) }
    stats = @hash[spec]
    assert_equal(1, stats.apdex_s)
    assert_equal(2, stats.apdex_t)
    assert_equal(3, stats.apdex_f)
    assert_equal(99, stats.min_call_time)
    assert_equal(99, stats.max_call_time)
  end

  def test_merge_merges
    specs = [
      NewRelic::MetricSpec.new('foo'),
      NewRelic::MetricSpec.new('bar'),
      NewRelic::MetricSpec.new('baz'),
      NewRelic::MetricSpec.new('baz', 'a_scope')
    ]

    hash1 = NewRelic::Agent::StatsHash.new
    hash1.record(specs[0], 1)
    hash1.record(specs[1], 2)
    hash1.record(specs[2], 3)

    hash2 = NewRelic::Agent::StatsHash.new
    hash2.record(specs[0], 1)
    hash2.record(specs[1], 2)
    hash2.record(specs[3], 3)

    hash1.merge!(hash2)

    assert_equal(4, hash1.to_h.keys.size)
    assert_equal(2, hash1[specs[0]].call_count)
    assert_equal(2, hash1[specs[1]].call_count)
    assert_equal(1, hash1[specs[2]].call_count)
    assert_equal(1, hash1[specs[3]].call_count)
  end

  def test_merge_re_sets_started_at_if_needed
    t0 = Time.at(0)
    t1 = Time.at(100)

    hash0 = NewRelic::Agent::StatsHash.new(t0)
    hash1 = NewRelic::Agent::StatsHash.new(t1)

    hash1.merge!(hash0)
    assert_equal(t0.to_f, hash1.started_at)
  end

  def test_merge_transaction_metrics
    specs = [
      NewRelic::MetricSpec.new('foo'),
      NewRelic::MetricSpec.new('bar'),
      NewRelic::MetricSpec.new('baz'),
      NewRelic::MetricSpec.new('baz', 'a_scope')
    ]

    hash = NewRelic::Agent::StatsHash.new
    hash.record(specs[0], 1)
    hash.record(specs[1], 2)
    hash.record(specs[2], 3)

    txn_metrics = NewRelic::Agent::TransactionMetrics.new
    txn_metrics.record_unscoped(specs[0].name, 1)
    txn_metrics.record_unscoped(specs[1].name, 2)
    txn_metrics.record_scoped_and_unscoped(specs[3].name, 3)

    hash.merge_transaction_metrics!(txn_metrics, 'a_scope')

    assert_equal(4, hash.to_h.keys.size)
    assert_equal(2, hash[specs[0]].call_count)
    assert_equal(2, hash[specs[1]].call_count)
    assert_equal(2, hash[specs[2]].call_count)
    assert_equal(1, hash[specs[3]].call_count)
  end

  def test_marshal_dump
    @hash.record(NewRelic::MetricSpec.new('foo'), 1)
    @hash.record(NewRelic::MetricSpec.new('bar'), 2)
    copy = Marshal.load(Marshal.dump(@hash))
    assert_equal(@hash, copy)
    assert_equal(@hash.started_at, copy.started_at)
  end

  # We can only fix up the default proc on Rubies that let us set it
  if {}.respond_to?(:default_proc=)
    def test_borked_default_proc_can_record_metric
      fake_borked_default_proc(@hash)

      @hash.record(DEFAULT_SPEC, 1)

      assert_equal(1, @hash[DEFAULT_SPEC].call_count)
    end

    def test_borked_default_proc_notices_agent_error
      fake_borked_default_proc(@hash)

      @hash.record(DEFAULT_SPEC, 1)

      assert_has_traced_error NewRelic::Agent::StatsHash::StatsHashLookupError
    end

    def test_borked_default_proc_heals_thyself
      fake_borked_default_proc(@hash)

      @hash.record(DEFAULT_SPEC, 1)
      reset_error_traces!

      @hash.record(NewRelic::MetricSpec.new('something/else/entirely'), 1)
      errors = harvest_error_traces!
      assert_equal 0, errors.size
    end
  end

  DEFAULT_SPEC = NewRelic::MetricSpec.new('foo')

  def fake_borked_default_proc(stats_hash)
    exception = NoMethodError.new("borked default proc gives a NoMethodError on `yield'")
    hash = stats_hash.instance_variable_get(:@unscoped)
    hash.default_proc = Proc.new { raise exception }
  end
end
