require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'action_controller/base'
#require 'new_relic/agent/agent_test_controller'

class AgentControllerTests < ActionController::TestCase
  
  self.controller_class = NewRelic::Agent::AgentTestController
  
  attr_accessor :agent
  
  def setup
    super
    Thread.current[:controller_ignored] = nil
    @agent = NewRelic::Agent.instance
    #    @agent.instrument_app
    agent.start :test, :test
    agent.transaction_sampler.harvest_slowest_sample
    NewRelic::Agent::AgentTestController.class_eval do
      newrelic_ignore :only => [:action_to_ignore, :entry_action]
    end
  end
  
  def teardown
    NewRelic::Agent.instance.shutdown
    Thread.current[:controller_ignored] = nil
    super
  end
  def test_metric__ignore
    engine = @agent.stats_engine
    get :action_to_ignore
    assert_equal true, Thread.current[:controller_ignored]
  end
  def test_metric__no_ignore
    engine = @agent.stats_engine
    index_stats = engine.get_stats_no_scope('Controller/new_relic/agent/agent_test/index')
    assert_difference 'index_stats.call_count' do
      get :index
    end
    assert_equal false, Thread.current[:controller_ignored]
  end
  def test_metric__dispatched
    engine = @agent.stats_engine
    get :entry_action
    assert_equal false, Thread.current[:controller_ignored]
    assert_nil engine.lookup_stat('Controller/agent_test/entry_action')
    assert_equal 1, engine.lookup_stat('Controller/new_relic/agent/agent_test/internal_action').call_count
  end
  def test_action_instrumentation
    begin
      get :index, :foo => 'bar'
      assert_match /bar/, @response.body
    #rescue ActionController::RoutingError
      # you might get here if you don't have the default route installed.
    end
  end
  
  def test_controller_params
    
    assert agent.transaction_sampler
    
    num_samples = NewRelic::Agent.instance.transaction_sampler.get_samples.length
    
    assert_equal "[FILTERED]", @controller._filter_parameters({'social_security_number' => 'test'})['social_security_number']
    
    get :index, 'social_security_number' => "001-555-1212"
    
    samples = agent.transaction_sampler.get_samples
    
    agent.transaction_sampler.expects(:notice_transaction).never
    
    assert_equal num_samples + 1, samples.length
    
    assert_equal "[FILTERED]", samples.last.params[:request_params]["social_security_number"]
    
  end
  
end
