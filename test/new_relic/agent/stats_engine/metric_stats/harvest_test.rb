require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper')) 
require 'new_relic/agent/stats_engine/metric_stats'
class NewRelic::Agent::StatsEngine::MetricStats::HarvestTest < Test::Unit::TestCase
  include NewRelic::Agent::StatsEngine::MetricStats::Harvest

  def test_merge_stats
    raise 'needs a test'
  end

  def test_get_stats_hash_from_hash
    raise 'needs a test'  
  end

  def test_get_stats_hash_from_engine
    raise 'needs a test'
  end

  def test_coerce_to_metric_spec
    raise 'needs a test'
  end

  def test_clone_and_reset_stats
    raise 'needs a test'
  end
  
  def test_merge_old_data!
    raise 'needs a test'
  end

  def test_add_data_to_send_unless_empty
    raise 'needs a test'
  end
end



