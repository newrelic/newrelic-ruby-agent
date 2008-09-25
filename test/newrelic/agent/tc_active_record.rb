require File.expand_path(File.join(File.dirname(__FILE__),'/../../../../../../test/test_helper'))


class TestModel < ActiveRecord::Base
  
  self.table_name = 'users'
  
end



class AgentControllerTests < Test::Unit::TestCase
  
  def setup
    super
    @agent = NewRelic::Agent.instance
    @agent.start :test, :test
  end
  
  def teardown
    @agent.shutdown
    super
  end
  
  def test_finder
   
    u = TestModel.find(:all)
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    assert_equal 1, s.call_count
    TestModel.find_all_by_email "nobody"
    
    se = NewRelic::Agent.instance.stats_engine
    se.inspect
    s = NewRelic::Agent.get_stats("ActiveRecord/TestModel/find")
    # FIXME this should pass but we're not instrumenting the dynamic finders    
    # assert_equal 2, s.call_count
  end
  
end
