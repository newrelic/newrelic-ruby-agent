require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'new_relic/agent/model_fixture'


class ActiveRecordTest < Test::Unit::TestCase
  
  
  def setup
    NewRelic::Agent.manual_start
    NewRelic::Agent::ModelFixture.setup
    NewRelic::Agent.instance.transaction_sampler.harvest
  end
  
  def teardown
    NewRelic::Agent.instance.stats_engine.harvest_timeslice_data Hash.new, Hash.new
    NewRelic::Agent::ModelFixture.teardown
  end
  def test_agent_setup
    assert NewRelic::Agent.instance.class == NewRelic::Agent::Agent
  end
  def test_finder
    NewRelic::Agent::ModelFixture.create :id => 0, :name => 'jeff'
    NewRelic::Agent::ModelFixture.find(:all)
    s = NewRelic::Agent.get_stats("ActiveRecord/NewRelic::Agent::ModelFixture/find")
    assert_equal 1, s.call_count
    NewRelic::Agent::ModelFixture.find_all_by_name "jeff"
    s = NewRelic::Agent.get_stats("ActiveRecord/NewRelic::Agent::ModelFixture/find")
    assert_equal 2, s.call_count
  end
  
  # multiple duplicate find calls should only cause metric trigger on the first
  # call.  the others are ignored.
  def test_query_cache
    NewRelic::Agent::ModelFixture.cache do
      m = NewRelic::Agent::ModelFixture.create :id => 0, :name => 'jeff'
      NewRelic::Agent::ModelFixture.find(:all)
      s = NewRelic::Agent.get_stats("ActiveRecord/NewRelic::Agent::ModelFixture/find")
      assert_equal 1, s.call_count
      
      10.times { NewRelic::Agent::ModelFixture.find m.id }
    end
    s = NewRelic::Agent.get_stats("ActiveRecord/NewRelic::Agent::ModelFixture/find")
    assert_equal 2, s.call_count    
  end
  
  def test_metric_names
    NewRelic::Agent.instance.stats_engine.harvest_timeslice_data({},{})
    m = NewRelic::Agent::ModelFixture.create :id => 0, :name => 'jeff'
    m = NewRelic::Agent::ModelFixture.find(m.id)
    m.id = 999
    m.save!
    m.id = 993
    m.destroy
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    
#    metrics = NewRelic::Agent.instance.stats_engine.metrics.select { |mname| mname =~ /ActiveRecord\/#{m.class.name}\// }.sort
    assert_equal %w[
      Database/DirectSQL
      ActiveRecord/all
      ActiveRecord/
      ActiveRecord/create
      ActiveRecord/columns
      ActiveRecord/destroy
      ActiveRecord/find
      ActiveRecord/indexes
      ActiveRecord/NewRelic::Agent::ModelFixture/create
      ActiveRecord/NewRelic::Agent::ModelFixture/columns
      ActiveRecord/NewRelic::Agent::ModelFixture/destroy
      ActiveRecord/NewRelic::Agent::ModelFixture/find
      ActiveRecord/NewRelic::Agent::ModelFixture/indexes
    ].sort, metrics.sort
    
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/#{m.class.name}/find").call_count
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/#{m.class.name}/create").call_count
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/#{m.class.name}/destroy").call_count
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/#{m.class.name}/columns").call_count
    assert_equal 1, NewRelic::Agent.get_stats("ActiveRecord/#{m.class.name}/indexes").call_count
    
  end
  
  def test_run_explains
    NewRelic::Agent::ModelFixture.find(:all)
    
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    
    segment = sample.root_segment.called_segments.first
    assert_match /^SELECT \* FROM ["`]?test_data["`]?$/i, segment.params[:sql].strip
    NewRelic::TransactionSample::Segment.any_instance.expects(:explain_sql).returns([])
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
  end
  def test_prepare_to_send
    NewRelic::Agent::ModelFixture.find(:all)
    
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    
    segment = sample.root_segment.called_segments.first
    assert_match /^SELECT /, segment.params[:sql]
    assert segment.duration > 0.0, "Segment duration must be greater than zero."
    sample = sample.prepare_to_send(:record_sql => :raw, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first
    assert_match /^SELECT /, segment.params[:sql]
    explanations = segment.params[:explanation]
    if isMysql? || isPostgres?
      assert_not_nil explanations, "No explains in segment: #{segment}"
      assert_equal 1, explanations.size,"No explains in segment: #{segment}" 
      assert_equal 1, explanations.first.size
    end
  end
  def test_transaction
    
    NewRelic::Agent::ModelFixture.find(:all)
    
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first
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
      assert_equal "1;SIMPLE;test_data;ALL;;;;;1;", explanations.first.first.join(";")
    end
    
    s = NewRelic::Agent.get_stats("ActiveRecord/NewRelic::Agent::ModelFixture/find")
    assert_equal 1, s.call_count
  end
  # These are only valid for rails 2.1 and later
  unless Rails::VERSION::STRING =~ /^(1\.|2\.0)/
    NewRelic::Agent::ModelFixture.class_eval do
      named_scope :jeffs, :conditions => { :name => 'Jeff' }
    end
    def test_named_scope
      NewRelic::Agent::ModelFixture.create :name => 'Jeff'
      s = NewRelic::Agent.get_stats("ActiveRecord/NewRelic::Agent::ModelFixture/find")
      before_count = s.call_count
      x = NewRelic::Agent::ModelFixture.jeffs.find(:all)
      assert_equal 1, x.size
      se = NewRelic::Agent.instance.stats_engine
      assert_equal before_count+1, s.call_count
    end
  end
  
  private 
  def isPostgres?
    NewRelic::Agent::ModelFixture.configurations[RAILS_ENV]['adapter'] =~ /postgres/
  end
  def isMysql?
    NewRelic::Agent::ModelFixture.connection.class.name =~ /mysql/i 
  end
end
