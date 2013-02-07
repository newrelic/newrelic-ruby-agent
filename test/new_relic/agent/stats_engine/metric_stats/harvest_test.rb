require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))
require 'new_relic/agent/stats_engine/metric_stats'

class NewRelic::Agent::StatsEngine::MetricStats::HarvestTest < Test::Unit::TestCase
  include NewRelic::Agent::StatsEngine::MetricStats::Harvest

  def with_stats_lock
    yield
  end

  attr_accessor :stats_hash
  def test_merge_stats_with_nil_stats
    self.stats_hash = NewRelic::Agent::StatsHash.new
    assert_equal({}, merge_stats({}, {}))
  end

  def test_coerce_to_metric_spec_metric_spec
    assert_equal NewRelic::MetricSpec.new, coerce_to_metric_spec(NewRelic::MetricSpec.new)
  end

  def test_coerce_to_metric_spec_string
    assert_equal NewRelic::MetricSpec.new('foo'), coerce_to_metric_spec('foo')
  end

  def test_merge_old_data_present
    metric_spec = mock('metric_spec')
    stats = mock('stats obj')
    stats.expects(:merge!).with('some stats')
    old_data = mock('old data')
    old_data.expects(:stats).returns('some stats')
    old_data_hash = {metric_spec => old_data}
    merge_old_data!(metric_spec, stats, old_data_hash)
  end

  def test_merge_old_data_nil
    metric_spec = mock('metric_spec')
    stats = mock('stats') # doesn't matter
    old_data_hash = {metric_spec => nil}
    merge_old_data!(metric_spec, stats, old_data_hash)
  end

  def test_add_data_to_send_unless_empty_when_is_empty
    stats = mock('stats')
    stats.expects(:is_reset?).returns(true)
    assert_equal nil, add_data_to_send_unless_empty(nil, stats, nil, nil)
  end

  def test_add_data_to_send_unless_empty_main
    data = mock('data hash')
    stats = mock('stats')
    stats.expects(:is_reset?).returns(false)
    metric_spec = mock('spec')

    NewRelic::MetricData.expects(:new).with(metric_spec, stats, nil).returns('metric data')
    data.expects(:[]=).with(metric_spec, 'metric data')
    add_data_to_send_unless_empty(data, stats, metric_spec, nil)
  end

  def test_add_data_to_send_unless_empty_with_id
    data = mock('data hash')
    stats = mock('stats')
    stats.expects(:is_reset?).returns(false)
    metric_spec = mock('spec')
    id = mock('id')

    NewRelic::MetricData.expects(:new).with(nil, stats, id).returns('metric data')
    data.expects(:[]=).with(metric_spec, 'metric data')
    assert_equal 'metric data', add_data_to_send_unless_empty(data, stats, metric_spec, id)
  end

  def test_merge_data_new_and_old_data
    stats = NewRelic::Stats.new
    stats.record_data_point(1.0)
    new_stats = NewRelic::Stats.new
    new_stats.record_data_point(2.0)

    metric_spec = NewRelic::MetricSpec.new('Custom/test/method')
    data_to_merge = {
      metric_spec => NewRelic::MetricData.new(metric_spec, stats, nil)
    }

    mock_stats_hash = mock('stats_hash')
    self.stats_hash = mock_stats_hash

    expected_stats_hash_to_merge = NewRelic::Agent::StatsHash.new
    expected_stats_hash_to_merge[metric_spec] = stats
    mock_stats_hash.expects(:merge!).with(expected_stats_hash_to_merge)

    merge_data(data_to_merge)
  end
end



