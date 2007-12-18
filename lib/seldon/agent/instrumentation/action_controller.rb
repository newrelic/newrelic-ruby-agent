
# Seldon instrumentation for controllers
if defined? ActionController

module ActionController
  class Base
    
    def perform_action_with_trace
      # don't trace if this is a web service...
      return perform_action_without_trace if is_web_service_controller?

      # generate metrics for all all controllers (no scope)
      self.class.trace_method_execution "Controller", false do 
        # generate metrics for this specific action
        self.class.trace_method_execution "Controller/#{controller_path}/#{action_name}" do 
          perform_action_without_trace
        end
      end
    end
    
    alias_method_chain :perform_action, :trace
    
    add_method_tracer :render, 'View/#{controller_name}/#{action_name}/Rendering'
    add_method_tracer :perform_invocation, 'WebService/#{controller_name}/#{args.first}'
   
    # trace the number of exceptions encountered 
    # TODO determine how to break these out: by error code, contoller class, error class? all of the above?
    add_method_tracer :rescue_action, 'Errors/Type/#{args.first.class}'
    add_method_tracer :rescue_action, 'Errors/Controller/#{self.class}'
    
    private
      def is_web_service_controller?
        # TODO this only covers the case for Direct implementation.
        self.class.read_inheritable_attribute("web_service_api")
      end
  end
end

end  
