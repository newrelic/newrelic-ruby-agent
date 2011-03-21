require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper')) 
require 'new_relic/agent/stats_engine/metric_stats'
class NewRelic::Agent::StatsEngine::MetricStats::HarvestTest < Test::Unit::TestCase
  include NewRelic::Agent::StatsEngine::MetricStats::Harvest
  
  attr_accessor :stats_hash
  def test_merge_stats_trivial
    self.stats_hash = {}
    merge_stats({}, {})
  end

  def test_get_stats_hash_from_hash
    assert_equal({}, get_stats_hash_from({}))
  end

  def test_get_stats_hash_from_engine
    assert_equal({}, get_stats_hash_from(NewRelic::Agent::StatsEngine.new))
  end

  def test_coerce_to_metric_spec_metric_spec
    assert_equal NewRelic::MetricSpec.new, coerce_to_metric_spec(NewRelic::MetricSpec.new)
  end

  def test_coerce_to_metric_spec_string
    assert_equal NewRelic::MetricSpec.new('foo'), coerce_to_metric_spec('foo')
  end  

  def test_clone_and_reset_stats_nil
    spec = NewRelic::MetricSpec.new('foo')
    stats = nil
    assert_raise(RuntimeError) do
      clone_and_reset_stats(spec, stats)
    end
  end

  def test_clone_and_reset_stats_present
    # spec is only used for debug output
    spec = nil
    stats = mock('stats')
    stats_clone = mock('stats_clone')
    stats.expects(:clone).returns(stats_clone)
    stats.expects(:reset)
    # should return a clone
    assert_equal stats_clone, clone_and_reset_stats(spec, stats)
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
    id = mock('id')

    data.expects(:[]=).with(metric_spec, is_a(NewRelic::MetricData))
    add_data_to_send_unless_empty(data, stats, metric_spec, id)
  end
end



