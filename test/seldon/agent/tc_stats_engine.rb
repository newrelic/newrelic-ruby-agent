require 'test/unit'
require 'seldon/agent/stats_engine'
require File.join(File.dirname(__FILE__),'mock_agent')


module Seldon::Agent
  class StatsEngineTests < Test::Unit::TestCase
    def setup
      @engine = StatsEngine.new
    end
  
    def test_get_no_scope
      s1 = @engine.get_stats "a"
      s2 = @engine.get_stats "a"
      s3 = @engine.get_stats "b"
      
      assert_not_nil s1
      assert_not_nil s2
      assert_not_nil s3
      
      assert s1 == s2
      assert s1 != s3
    end
    
    def test_harvest
      s1 = @engine.get_stats "a"
      s2 = @engine.get_stats "c"
      
      s1.trace_call 10
      s2.trace_call 1
      s2.trace_call 3
      
      assert @engine.get_stats("a").call_count == 1
      assert @engine.get_stats("a").total_call_time == 10
      
      assert @engine.get_stats("c").call_count == 2
      assert @engine.get_stats("c").total_call_time == 4
      
      metric_data = @engine.harvest_timeslice_data({}).values
      
      # after harvest, all the metrics should be reset
      assert @engine.get_stats("a").call_count == 0
      assert @engine.get_stats("a").total_call_time == 0
      
      assert @engine.get_stats("c").call_count == 0
      assert @engine.get_stats("c").total_call_time == 0

      metric_data = metric_data.reverse if metric_data[0].metric_spec.name != "a"

      assert metric_data[0].metric_spec.name == "a"

      assert metric_data[0].stats.call_count == 1
      assert metric_data[0].stats.total_call_time == 10
    end
    
    def test_harvest_with_merge
      s = @engine.get_stats "a"
      s.trace_call 1
      
      assert @engine.get_stats("a").call_count == 1
      
      harvest = @engine.harvest_timeslice_data({})
      assert s.call_count == 0
      s.trace_call 2
      assert s.call_count == 1
      
      # this calk should merge the contents of the previous harvest,
      # so the stats for metric "a" should have 2 data points
      harvest = @engine.harvest_timeslice_data(harvest)
      stats = harvest.fetch(Seldon::MetricSpec.new("a")).stats
      assert stats.call_count == 2
      assert stats.total_call_time == 3
    end
    
    def test_scope
      @engine.push_scope "scope1"
      assert @engine.peek_scope == "scope1"
      
      @engine.push_scope "scope2"
      @engine.pop_scope
      
      scoped = @engine.get_stats "a"
      scoped.trace_call 3
      
      assert scoped.total_call_time == 3
      unscoped = @engine.get_stats "a"
      
      assert scoped == @engine.get_stats("a")
      assert unscoped.total_call_time == 3
    end
  end
end
