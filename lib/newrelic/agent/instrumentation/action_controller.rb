require 'set'

# NewRelic instrumentation for controllers
if defined? ActionController

class ActionController::Base
  def perform_action_with_trace
    return perform_action_without_trace if self.class.read_inheritable_attribute('do_not_trace')
    
    agent = NewRelic::Agent.instance
    
    # generate metrics for all all controllers (no scope)
    self.class.trace_method_execution "Controller", false do 
      # generate metrics for this specific action
      path = "#{controller_path}/#{action_name}"
      
      # TODO should we just make the transaction name the path, or the metric name for the controller?
      agent.stats_engine.transaction_name ||= "Controller/#{path}"
      
      self.class.trace_method_execution "Controller/#{path}" do 
        # send request and parameter info to the transaction sampler
        NewRelic::Agent.instance.transaction_sampler.notice_transaction(path, params)
        
        # run the action
        perform_action_without_trace
      end
    end
    
  ensure
    # clear out the name of the traced transaction under all circumstances
    agent.stats_engine.transaction_name = nil
  end
  
  alias_method_chain :perform_action, :trace
  
  add_method_tracer :render, 'View/#{controller_name}/#{action_name}/Rendering'
  
  # ActionWebService is now an optional part of Rails as of 2.0
  if method_defined? :perform_invocation
    add_method_tracer :perform_invocation, 'WebService/#{controller_name}/#{args.first}'
  end
 
  # trace the number of exceptions encountered 
  # TODO determine how to break these out: by error code, contoller class, error class? all of the above?
  add_method_tracer :rescue_action, 'Errors/Type/#{args.first.class}', false
  add_method_tracer :rescue_action, 'Errors/Controller/#{self.class}', false
  
  protected
    def is_web_service_controller?
      # TODO this only covers the case for Direct implementation.
      self.class.read_inheritable_attribute("web_service_api")
    end
  end
end  


