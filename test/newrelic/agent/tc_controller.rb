require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 

NewRelic::Agent.instance.instrument_app

class AgentTestController < ActionController::Base
  filter_parameter_logging :social_security_number
  
  def _filter_parameters(params)
    filter_parameters params
  end
  
  newrelic_ignore :only => :action_to_ignore
  
  def action_to_ignore(*args)
  end
  
end



class AgentControllerTests < Test::Unit::TestCase
  
  attr_accessor :agent
  def setup
    super
    @agent = NewRelic::Agent.instance
    @agent.start :test, :test
  end
  
  def teardown
    @agent.shutdown
    super
  end
  
  def test_controller_params
    
    assert agent.transaction_sampler
    
    controller = AgentTestController.new
    
    assert_equal 0, NewRelic::Agent.instance.transaction_sampler.get_samples.length
    
    assert_equal "[FILTERED]", controller._filter_parameters({'social_security_number' => 'test'})['social_security_number']
    
    controller.process(ActionController::TestRequest.new('social_security_number' => "001-555-1212"), ActionController::TestResponse.new)
    
    samples = NewRelic::Agent.instance.transaction_sampler.get_samples
    
    NewRelic::Agent.instance.transaction_sampler.expects(:notice_transaction).never
    
    assert_equal 1, samples.length
    
    assert_equal Hash["social_security_number", "[FILTERED]"], samples[0].params[:request_params]

  end
  
end
