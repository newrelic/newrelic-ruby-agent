require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::SqlSamplerTest < Test::Unit::TestCase
  
  def setup
    agent = NewRelic::Agent.instance
    stats_engine = NewRelic::Agent::StatsEngine.new
    agent.stubs(:stats_engine).returns(stats_engine)
    @sampler = NewRelic::Agent::SqlSampler.new
    stats_engine.sql_sampler = @sampler
  end
  
  def test_notice_first_scope_push
    assert_nil Thread.current[:transaction_sql]    
    @sampler.notice_first_scope_push nil
    assert_not_nil Thread.current[:transaction_sql]
    @sampler.notice_scope_empty
    assert_nil Thread.current[:transaction_sql]
  end
  
  def test_notice_sql_no_transaction
    assert_nil Thread.current[:transaction_sql]    
    @sampler.notice_sql "select * from test", "Database/test/select", nil, 10
  end

  def test_notice_sql
    @sampler.notice_first_scope_push nil
    @sampler.notice_sql "select * from test", "Database/test/select", nil, 1.5
    @sampler.notice_sql "select * from test2", "Database/test2/select", nil, 1.3
    # this sql will not be captured
    @sampler.notice_sql "select * from test", "Database/test/select", nil, 0
    assert_not_nil Thread.current[:transaction_sql]
    assert_equal 2, Thread.current[:transaction_sql].count
  end
  
  def test_harvest_slow_sql
    @sampler.harvest_slow_sql "WebTransaction/Controller/c/a", "/c/a", [NewRelic::Agent::SlowSql.new("select * from test", "Database/test/select", 1.5), 
      NewRelic::Agent::SlowSql.new("select * from test", "Database/test/select", 1.2), 
      NewRelic::Agent::SlowSql.new("select * from test2", "Database/test2/select", 1.1)]
      
    assert_equal 2, @sampler.sql_traces.count
  end
  
  def test_sql_aggregation
    sql_trace = NewRelic::Agent::SqlTrace.new("select * from test", 
      NewRelic::Agent::SlowSql.new("select * from test", "Database/test/select", 1.2), "tx_name", "uri")
      
    sql_trace.aggregate NewRelic::Agent::SlowSql.new("select * from test", "Database/test/select", 1.5), "slowest_tx_name", "slow_uri"
    sql_trace.aggregate NewRelic::Agent::SlowSql.new("select * from test", "Database/test/select", 1.1), "other_tx_name", "uri2"
    
    assert_equal 3, sql_trace.stats.call_count
    assert_equal "slowest_tx_name", sql_trace.transaction_name
    assert_equal "slow_uri", sql_trace.uri
    assert_equal 1.5, sql_trace.stats.max_call_time
  end
  
  def test_harvest
    @sampler.harvest_slow_sql "WebTransaction/Controller/c/a", "/c/a", [NewRelic::Agent::SlowSql.new("select * from test", "Database/test/select", 1.5), 
      NewRelic::Agent::SlowSql.new("select * from test", "Database/test/select", 1.2), 
      NewRelic::Agent::SlowSql.new("select * from test2", "Database/test2/select", 1.1)]
      
    sql_traces = @sampler.harvest
    assert_equal 2, sql_traces.count
  end
end