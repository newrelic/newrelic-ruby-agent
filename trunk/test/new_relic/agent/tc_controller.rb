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
  end
end

class AgentControllerTests < ActionController::TestCase
  
  self.controller_class = AgentTestController
  
  attr_accessor :agent
  
  def setup
    super
    @agent = NewRelic::Agent.instance
    #    @agent.instrument_app
    agent.start :test, :test
    agent.transaction_sampler.harvest_slowest_sample
  end
  
  def teardown
    NewRelic::Agent.instance.shutdown
    super
  end
  
  def test_action_instrumentation
    get :index, :foo => 'bar'
    assert_match /bar/, @response.body
  end
  
  def test_controller_params
    
    AgentTestController.class_eval do
      newrelic_ignore :only => :action_to_ignore
    end
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
