require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'action_controller/base'


class AgentTestController < ActionController::Base
  filter_parameter_logging :social_security_number
  def index
    render :text => params.inspect
  end
  def _filter_parameters(params)
    filter_parameters params
  end
  def action_to_render
    render :text => params.inspect
  end
  def action_to_ignore
    render :text => 'unmeasured'
  end
  def entry_action
    perform_action_with_newrelic_trace('internal_action') do
      internal_action
    end    
  end
  private
  def internal_action
    render :text => 'internal action'
  end
end

class AgentControllerTests < ActionController::TestCase
  
  self.controller_class = AgentTestController
  
  attr_accessor :agent
  
  def setup
    super
    Thread.current[:controller_ignored] = nil
    @agent = NewRelic::Agent.instance
    #    @agent.instrument_app
    agent.start :test, :test
    agent.transaction_sampler.harvest_slowest_sample
    AgentTestController.class_eval do
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
    index_stats = engine.get_stats_no_scope('Controller/agent_test/index')
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
    assert_equal 1, engine.lookup_stat('Controller/agent_test/internal_action').call_count
  end
  def test_action_instrumentation
    get :index, :foo => 'bar'
    assert_match /bar/, @response.body
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
