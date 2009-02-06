require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'new_relic/agent/model_fixture'


class ActiveRecordInstrumentationTests < Test::Unit::TestCase
  
  def setup
    super
    NewRelic::Agent::ModelFixture.setup
    @agent = NewRelic::Agent.instance
    @agent.start :test, :test
    @agent.transaction_sampler.harvest_slowest_sample
  end
  
  def teardown
    @agent.shutdown
    @agent.stats_engine.harvest_timeslice_data Hash.new, Hash.new
    NewRelic::Agent::ModelFixture.teardown
    super
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
  
  def test_run_explains
    NewRelic::Agent::ModelFixture.find(:all)
    sample = @agent.transaction_sampler.harvest_slowest_sample
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_match /^SELECT \* FROM ["`]test_data["`]$/i, segment.params[:sql].strip
    NewRelic::TransactionSample::Segment.any_instance.expects(:explain_sql).returns([])
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
  end
  def test_prepare_to_send
    NewRelic::Agent::ModelFixture.find(:all)
    sample = @agent.transaction_sampler.harvest_slowest_sample
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_match /^SELECT /, segment.params[:sql]
    assert segment.duration > 0.0, "Segment duration must be greater than zero."
    sample = sample.prepare_to_send(:record_sql => :raw, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
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
    sample = @agent.transaction_sampler.harvest_slowest_sample
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
      assert_equal "1;SIMPLE;test_data;ALL;;;;;1;", explanations.first.first.join(";")
    end
    
    s = NewRelic::Agent.get_stats("ActiveRecord/NewRelic::Agent::ModelFixture/find")
    assert_equal 1, s.call_count
  end
  
  private 
  def isPostgres?
    NewRelic::Agent::ModelFixture.configurations[RAILS_ENV]['adapter'] =~ /postgres/
  end
  def isMysql?
    NewRelic::Agent::ModelFixture.connection.class.name =~ /mysql/i 
  end
end
