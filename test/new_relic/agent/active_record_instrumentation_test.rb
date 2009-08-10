require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'active_record_fixtures'

class ActiveRecordInstrumentationTest < Test::Unit::TestCase
  
  def setup
    super
    NewRelic::Agent.manual_start
    NewRelic::Agent.instance.stats_engine.clear_stats
    ActiveRecordFixtures.setup
    NewRelic::Agent.instance.transaction_sampler.harvest
  rescue
    puts e
    puts e.backtrace.join("\n")
  end
  
  def teardown
    super
    ActiveRecordFixtures.teardown
  end
  def test_agent_setup
    assert NewRelic::Agent.instance.class == NewRelic::Agent::Agent
  end
  def test_finder
    ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'
    ActiveRecordFixtures::Order.find(:all)
    s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
    assert_equal 1, s.call_count
    ActiveRecordFixtures::Order.find_all_by_name "jeff"
    s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
    assert_equal 2, s.call_count
  end
  
  # multiple duplicate find calls should only cause metric trigger on the first
  # call.  the others are ignored.
  def test_query_cache
    ActiveRecordFixtures::Order.cache do
      m = ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'
      ActiveRecordFixtures::Order.find(:all)
      s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
      assert_equal 1, s.call_count
      
      10.times { ActiveRecordFixtures::Order.find m.id }
    end
    s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
    assert_equal 2, s.call_count    
  end
  
  def test_metric_names
    m = ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'
    m = ActiveRecordFixtures::Order.find(m.id)
    m.id = 999
    m.save!
    
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    #   This doesn't work on hudson because the sampler metrics creep in.    
    #   metrics = NewRelic::Agent.instance.stats_engine.metrics.select { |mname| mname =~ /ActiveRecord\/ActiveRecordFixtures::Order\// }.sort
    expected = %W[
      ActiveRecord/all
      ActiveRecord/create
      ActiveRecord/find
      ActiveRecord/ActiveRecordFixtures::Order/create
      ActiveRecord/ActiveRecordFixtures::Order/find
      ]
    expected += %W[ActiveRecord/save ActiveRecord/ActiveRecordFixtures::Order/save] if NewRelic::Control.instance.rails_version < '2.1.0'   
    compare_metrics expected, metrics
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find").call_count
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/create").call_count
  end
  def test_join_metrics
    m = ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'
    m = ActiveRecordFixtures::Order.find(m.id)
    s = m.shipments.create
    m.shipments.to_a
    m.destroy
    
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    #   This doesn't work on hudson because the sampler metrics creep in.    
    #   metrics = NewRelic::Agent.instance.stats_engine.metrics.select { |mname| mname =~ /ActiveRecord\/ActiveRecordFixtures::Order\// }.sort
    compare_metrics %W[
    ActiveRecord/all
    ActiveRecord/destroy
    ActiveRecord/ActiveRecordFixtures::Order/destroy
    Database/SQL/insert
    Database/SQL/delete
    ActiveRecord/create
    ActiveRecord/find
    ActiveRecord/ActiveRecordFixtures::Order/create
    ActiveRecord/ActiveRecordFixtures::Order/find
    ActiveRecord/ActiveRecordFixtures::Shipment/find
    ActiveRecord/ActiveRecordFixtures::Shipment/create
    ], metrics
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find").call_count
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Shipment/find").call_count
    assert_equal 1, NewRelic::Agent.get_stats("Database/SQL/insert").call_count
    assert_equal 1, NewRelic::Agent.get_stats("Database/SQL/delete").call_count
  end
  def test_direct_sql
    list = ActiveRecordFixtures::Order.connection.select_rows "select * from #{ActiveRecordFixtures::Order.table_name}"
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics %W[
    ActiveRecord/all
    Database/SQL/select
    ], metrics
    assert_equal 1, NewRelic::Agent.get_stats("Database/SQL/select").call_count
  end
  
  def test_blocked_instrumentation
    ActiveRecordFixtures::Order.add_delay
    NewRelic::Agent.disable_all_tracing do
      ActiveRecordFixtures::Order.find(:all)
    end
    assert_nil NewRelic::Agent.instance.transaction_sampler.last_sample
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics [], metrics
  end
  def test_run_explains
    ActiveRecordFixtures::Order.add_delay
    ActiveRecordFixtures::Order.find(:all)
    
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_match /^SELECT \* FROM ["`]?#{ActiveRecordFixtures::Order.table_name}["`]?$/i, segment.params[:sql].strip
    NewRelic::TransactionSample::Segment.any_instance.expects(:explain_sql).returns([])
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
  end
  def test_prepare_to_send
    ActiveRecordFixtures::Order.add_delay
    ActiveRecordFixtures::Order.find(:all)
    
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    # 
    sql_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_match /^SELECT /, sql_segment.params[:sql]
    assert sql_segment.duration > 0.0, "Segment duration must be greater than zero."
    sample = sample.prepare_to_send(:record_sql => :raw, :explain_enabled => true, :explain_sql => 0.0)
    sql_segment = sample.root_segment.called_segments.first.called_segments.first
    assert_match /^SELECT /, sql_segment.params[:sql]
    explanations = sql_segment.params[:explanation]
    if isMysql? || isPostgres?
      assert_not_nil explanations, "No explains in segment: #{sql_segment}"
      assert_equal 1, explanations.size,"No explains in segment: #{sql_segment}" 
      assert_equal 1, explanations.first.size
    end
  end
  def test_transaction
    ActiveRecordFixtures::Order.add_delay
    ActiveRecordFixtures::Order.find(:all)
    
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_nil segment.params[:sql], "SQL should have been removed."
    explanations = segment.params[:explanation]
    if isMysql? || isPostgres?
      assert_not_nil explanations, "No explains in segment: #{segment}"
      assert_equal 1, explanations.size,"No explains in segment: #{segment}" 
      assert_equal 1, explanations.first.size
    end    
    if isPostgres?
      assert_equal Array, explanations.class
      assert_equal Array, explanations[0].class
      assert_equal Array, explanations[0][0].class
      assert_match /Seq Scan on test_data/, explanations[0][0].join(";") 
    elsif isMysql?
      assert_equal "1;SIMPLE;#{ActiveRecordFixtures::Order.table_name};ALL;;;;;1;", explanations.first.first.join(";")
    end
    
    s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
    assert_equal 1, s.call_count
  end
  # These are only valid for rails 2.1 and later
  if NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("2.1.0")
    ActiveRecordFixtures::Order.class_eval do
      named_scope :jeffs, :conditions => { :name => 'Jeff' }
    end
    def test_named_scope
      ActiveRecordFixtures::Order.create :name => 'Jeff'
      s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
      before_count = s.call_count
      x = ActiveRecordFixtures::Order.jeffs.find(:all)
      assert_equal 1, x.size
      se = NewRelic::Agent.instance.stats_engine
      assert_equal before_count+1, s.call_count
    end
  end
  
  # This is to make sure the all metric is recorded for exceptional cases
  def test_error_handling
    # have the AR select throw an error
    ActiveRecordFixtures::Order.connection.stubs(:log_info).with do | sql, x, y |
      raise "Error" if sql =~ /select/
      true
    end
    ActiveRecordFixtures::Order.connection.select_rows "select * from #{ActiveRecordFixtures::Order.table_name}" rescue nil
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics %W[
    ActiveRecord/all
    Database/SQL/select
    ], metrics
    assert_equal 1, NewRelic::Agent.get_stats("Database/SQL/select").call_count
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/all").call_count
  end
  
  private
  
  def compare_metrics expected_list, actual_list
    actual = Set.new actual_list
    expected = Set.new expected_list
    assert_equal expected, actual, "extra: #{(actual - expected).to_a.join(", ")}; missing: #{(expected - actual).to_a.join(", ")}"
  end
  def isPostgres?
    ActiveRecordFixtures::Order.configurations[RAILS_ENV]['adapter'] =~ /postgres/
  end
  def isMysql?
    ActiveRecordFixtures::Order.connection.class.name =~ /mysql/i 
  end
end
