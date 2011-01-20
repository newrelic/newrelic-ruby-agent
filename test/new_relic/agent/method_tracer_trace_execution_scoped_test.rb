require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
class NewRelic::Agent::AgentStartTest < Test::Unit::TestCase
  require 'new_relic/agent/method_tracer'
  include NewRelic::Agent::MethodTracer::InstanceMethods::TraceExecutionScoped
  
  def test_trace_disabled_negative
    self.expects(:traced?).returns(false)
    options = {:force => false}
    assert !(trace_disabled?(options))
  end
  
  def test_trace_disabled_negative
    self.expects(:traced?).returns(false)
    options = {:force => true}
    assert !(trace_disabled?(options))
  end

  def test_get_stats_unscoped
    fake_engine = mocked_object('stat_engine')
    fake_engine.expects(:get_stats_no_scope).with('foob').returns('fakestats')
    assert_equal 'fakestats', get_stats_unscoped('foob')
  end

  def test_get_stats_scoped_scoped_only
    fake_engine = mocked_object('stat_engine')    
    fake_engine.expects(:get_stats).with('foob', true, true).returns('fakestats')
    assert_equal 'fakestats', get_stats_scoped('foob', true)
  end

  def test_get_stats_scoped_no_scoped_only
    fake_engine = mocked_object('stat_engine')    
    fake_engine.expects(:get_stats).with('foob', true, false).returns('fakestats')
    assert_equal 'fakestats', get_stats_scoped('foob', false)
  end

  def test_stat_engine
    assert_equal agent_instance.stats_engine, stat_engine
  end

  def test_agent_instance
    assert_equal NewRelic::Agent.instance, agent_instance
  end

  private

  def mocked_object(name)
    object = mock(name)
    self.stubs(name).returns(object)
    object
  end
  
  
  def mocked_log
    mocked_object('log')
  end


  def mocked_control
    mocked_object('control')
  end
end

