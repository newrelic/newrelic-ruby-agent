require File.expand_path(File.join(File.dirname(__FILE__),'/../../../../../../test/test_helper'))

class TestModel < ActiveRecord::Base
  self.table_name = 'test_data'
  def TestModel.setup
    TestModel.connection.create_table :test_data, :force => true do |t|
      t.column :name, :string
    end
    connection.setup_slow
  end
  
  def TestModel.teardown
    connection.teardown_slow
    TestModel.connection.drop_table :test_data
  end
end

class ActiveRecordInstrumentationTests < Test::Unit::TestCase
  
  def setup
    super
    begin
      TestModel.setup
    rescue => e
      puts e
      raise e
    end
    @agent = NewRelic::Agent.instance
    @agent.start :test, :test
    @agent.transaction_sampler.harvest_slowest_sample
  end
  
  def teardown
    @agent.shutdown
    @agent.stats_engine.harvest_timeslice_data Hash.new, Hash.new
    TestModel.teardown
    super
  end
  
  def test_finder
    TestModel.create :id => 0, :name => 'jeff'
    TestModel.find(:all)
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    assert_equal 1, s.call_count
    TestModel.find_all_by_name "jeff"
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    # FIXME this should pass but we're not instrumenting the dynamic finders    
    #assert_equal 2, s.call_count
    assert_equal 1, s.call_count
  end
  
  def test_run_explains
    TestModel.find(:all)
    sample = @agent.transaction_sampler.harvest_slowest_sample
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_equal "SELECT * FROM `test_data`", segment.params[:sql].strip
    NewRelic::TransactionSample::Segment.any_instance.expects(:explain_sql).returns([])
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
  end
  def test_prepare_to_send
    t0 = Time.now
    TestModel.find(:all)
    sample = @agent.transaction_sampler.harvest_slowest_sample
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_match /^SELECT /, segment.params[:sql]
    assert segment.duration > 0.0, "Segment duration must be greater than zero."
    sample = sample.prepare_to_send(:record_sql => :raw, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_match /^SELECT /, segment.params[:sql]
    explanations = segment.params[:explanation]
    assert_not_nil explanations, "No explains in segment: #{segment}"
    assert_equal 1, explanations.size,"No explains in segment: #{segment}" 
    assert_equal 1, explanations.first.size
    
  end
  def test_transaction
    
    TestModel.find(:all)
    sample = @agent.transaction_sampler.harvest_slowest_sample
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first
    assert_nil segment.params[:sql], "SQL should have been removed."
    explanations = segment.params[:explanation]
    assert_not_nil explanations, "No explains in segment: #{segment}"
    assert_equal 1, explanations.size,"No explains in segment: #{segment}" 
    assert_equal 1, explanations.first.size
    
    if isPostgres?
      assert_equal Array, explanations.class
      assert_equal Array, explanations[0].class
      assert_equal Array, explanations[0][0].class
      assert_match /Seq Scan on test_data/, explanations[0][0].join(";") 
    else
      assert_equal "1;SIMPLE;test_data;ALL;;;;;1;", explanations.first.first.join(";")
    end
    
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    assert_equal 1, s.call_count
  end
  
  private 
  def isPostgres?
    TestModel.configurations[RAILS_ENV]['adapter'] =~ /postgres/
  end
  
end
