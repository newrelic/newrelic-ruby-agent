
if defined? ActionController 

  ActionController::Base.class_eval do
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    
    # Compare with #alias_method_chain, which is not available in 
    # Rails 1.1:
    alias_method :perform_action_without_newrelic_trace, :perform_action
    alias_method :perform_action, :perform_action_with_newrelic_trace
    private :perform_action
    
    add_method_tracer :render, 'View/#{newrelic_metric_path}/Rendering'
    
    def self.newrelic_ignore_attr=(value)
      write_inheritable_attribute('do_not_trace', value)
    end
    def self.newrelic_ignore_attr
      read_inheritable_attribute('do_not_trace')
    end

    # determine the path that is used in the metric name for
    # the called controller action
    def newrelic_metric_path(action_name_override = nil)
      action_part = action_name_override || action_name
      if action_name_override || self.class.action_methods.include?(action_part)
        "#{self.class.controller_path}/#{action_part}"
      else
        "#{self.class.controller_path}/(other)"
      end
    end
  end  
else
  NewRelic::Agent.instance.log.debug "WARNING: ActionController instrumentation not added"
end  
