require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'action_controller/base'

class AgentControllerTest < ActionController::TestCase
  
  self.controller_class = NewRelic::Agent::AgentTestController
  
  attr_accessor :agent
  
  # Normally you can do this with #setup but for some reason in rails 2.0.2
  # setup is not called.
  def initialize name
    super name
    Thread.current[:newrelic_ignore_controller] = nil
    NewRelic::Agent.manual_start
    @agent = NewRelic::Agent.instance
    #    @agent.instrument_app
    agent.transaction_sampler.harvest
    NewRelic::Agent::AgentTestController.class_eval do
      newrelic_ignore :only => [:action_to_ignore, :entry_action, :base_action]
      newrelic_ignore_apdex :only => :action_to_ignore_apdex
    end
  end
  
  def teardown
    Thread.current[:newrelic_ignore_controller] = nil
    @agent.stats_engine.clear_stats
    super
  end
  
  def test_metric__ignore
    engine = @agent.stats_engine
    get :action_to_ignore
    assert_equal true, Thread.current[:newrelic_ignore_controller]
  end
  def test_metric__ignore_base
    engine = @agent.stats_engine
    get :base_action
    assert_equal true, Thread.current[:newrelic_ignore_controller]
  end
  def test_metric__no_ignore
    engine = @agent.stats_engine
    path = 'new_relic/agent/agent_test/index'
    cpu_stats = engine.get_stats_no_scope("ControllerCPU/#{path}")
    index_stats = engine.get_stats_no_scope("Controller/#{path}")
    index_apdex_stats = engine.get_custom_stats("Apdex/#{path}", NewRelic::ApdexStats)
    assert_difference 'index_stats.call_count' do
      assert_difference 'index_apdex_stats.call_count' do
        assert_difference 'cpu_stats.call_count' do
          get :index
        end
      end
    end
    assert_nil Thread.current[:newrelic_ignore_controller]
  end
  def test_metric__ignore_apdex
    engine = @agent.stats_engine
    path = 'new_relic/agent/agent_test/action_to_ignore_apdex'
    cpu_stats = engine.get_stats_no_scope("ControllerCPU/#{path}")
    index_stats = engine.get_stats_no_scope("Controller/#{path}")
    index_apdex_stats = engine.get_custom_stats("Apdex/#{path}", NewRelic::ApdexStats)
    assert_difference 'index_stats.call_count' do
      assert_no_difference 'index_apdex_stats.call_count' do
        assert_difference 'cpu_stats.call_count' do
          get :action_to_ignore_apdex
        end
      end
    end
    assert_nil Thread.current[:newrelic_ignore_controller]
    
  end
  def test_metric__dispatched
    engine = @agent.stats_engine
    get :entry_action
    assert_nil Thread.current[:newrelic_ignore_controller]
    assert_nil engine.lookup_stat('Controller/agent_test/entry_action')
    assert_nil engine.lookup_stat('Controller/new_relic/agent/agent_test/internal_action')
    assert_not_nil engine.lookup_stat('Controller/new_relic/agent/agent_test/internal_traced_action')
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
    
    num_samples = NewRelic::Agent.instance.transaction_sampler.samples.length
    
    assert_equal "[FILTERED]", @controller._filter_parameters({'social_security_number' => 'test'})['social_security_number']
    
    get :index, 'social_security_number' => "001-555-1212"
    
    samples = agent.transaction_sampler.samples
    
    agent.transaction_sampler.expects(:notice_transaction).never
    
    assert_equal num_samples + 1, samples.length
    
    assert_equal "[FILTERED]", samples.last.params[:request_params]["social_security_number"]
    
  end
  
end
