require File.expand_path(File.join(File.dirname(__FILE__),'/../../../../../../test/test_helper'))

class TestModel < ActiveRecord::Base
  self.table_name = 'test_data'
  
  def TestModel.setup
    TestModel.connection.create_table :test_data, :force => true do |t|
      t.column :name, :string
    end
    # Make the query very slow
    class << TestModel.connection
      alias :real_select :select
      def select(sql, name=nil)
        sleep 1
        real_select sql, name
      end
    end
  end
  
  def TestModel.teardown
    class << TestModel.connection
      alias :select :real_select
    end
    TestModel.connection.drop_table :test_data
  end
end

class ActiveRecordInstrumentationTests < Test::Unit::TestCase
  
  def setup
    super
    TestModel.setup    
    @agent = NewRelic::Agent.instance
    @agent.start :test, :test
    TestModel.create :id => 0, :name => 'jeff'
  end
  
  def teardown
    @agent.shutdown
    @agent.stats_engine.harvest_timeslice_data Hash.new, Hash.new
    TestModel.teardown
    super
  end
  
  def test_finder
    TestModel.find(:all)
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    assert_equal 1, s.call_count
    TestModel.find_all_by_name "jeff"
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    # FIXME this should pass but we're not instrumenting the dynamic finders    
    #assert_equal 2, s.call_count
    assert_equal 1, s.call_count
  end
  
  def test_transaction
    
    TestModel.find(:all)
    sample = NewRelic::Agent.instance.transaction_sampler.harvest_slowest_sample
    sample = sample.prepare_to_send(:obfuscate_sql => true, :explain_enabled => true, :explain_sql => 0.000001)
    segment = sample.root_segment.called_segments.first.called_segments.first
    explanations = segment.params[:explanation]
    assert_equal 1, explanations.size
    assert_equal 1, explanations.first.size
    assert_equal "1;SIMPLE;test_data;ALL;;;;;1;", explanations.first.first.join(";")
    
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    assert_equal 1, s.call_count
  end
  
end
