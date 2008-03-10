require 'set'

# NewRelic instrumentation for controllers
if defined? ActionController


module ActionController
  class Base
    def perform_action_with_newrelic_trace
      agent = NewRelic::Agent.instance
      return perform_action_without_newrelic_trace if self.class.read_inheritable_attribute('do_not_trace')
    
      # generate metrics for all all controllers (no scope)
      self.class.trace_method_execution "Controller", false do 
        # generate metrics for this specific action
        path = _determine_metric_path
      
        # TODO should we just make the transaction name the path, or the metric name for the controller?
        agent.stats_engine.transaction_name ||= "Controller/#{path}" if agent.stats_engine
      
        self.class.trace_method_execution "Controller/#{path}" do 
          # send request and parameter info to the transaction sampler
          NewRelic::Agent.instance.transaction_sampler.notice_transaction(path, request, params)
        
          # run the action
          perform_action_without_newrelic_trace
        end
      end
    
    ensure
      # clear out the name of the traced transaction under all circumstances
      agent.stats_engine.transaction_name = nil
    end
  
    alias_method_chain :perform_action, :newrelic_trace
  
    add_method_tracer :render, 'View/#{_determine_metric_path}/Rendering'
  
    # ActionWebService is now an optional part of Rails as of 2.0
    if method_defined? :perform_invocation
      add_method_tracer :perform_invocation, 'WebService/#{controller_name}/#{args.first}'
    end
  
 
    # trace the number of exceptions encountered 
    # TODO determine how to break these out: by error code, contoller class, error class? all of the above?
    # add_method_tracer :rescue_action, 'Errors/Type/#{args.first.class}', false
    # add_method_tracer :rescue_action, 'Errors/Controller/#{self.class}', false
  
    private
      # determine the path that is used in the metric name for
      # the called controller action
      def _determine_metric_path
        if self.class.action_methods.include?(action_name)
          "#{self.class.controller_path}/#{action_name}"
        else
          "#{self.class.controller_path}/(other)"
        end
      end
  end

end

end  


