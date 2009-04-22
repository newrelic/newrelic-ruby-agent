
if defined? ActionController
  
  case Rails::VERSION::STRING

    when /^(1\.|2\.0)/  # Rails 1.* - 2.0
    ActionController::Base.class_eval do
      add_method_tracer :render, 'View/#{newrelic_metric_path}/Rendering'
    end  

    when /^2\.1\./  # Rails 2.1
    ActionView::PartialTemplate.class_eval do
      add_method_tracer :render, 'View/#{path_without_extension}.#{@view.template_format}.#{extension}/Partial'
    end
    ActionView::Template.class_eval do
      add_method_tracer :render, 'View/#{path_without_extension}.#{@view.template_format}.#{extension}/Rendering'
    end

    when /^2\./   # Rails 2.2-2.*
    ActionView::RenderablePartial.module_eval do
      add_method_tracer :render_partial, 'View/#{path}/Partial'
    end
    ActionView::Template.class_eval do
      add_method_tracer :render, 'View/#{path}/Rendering'
    end
  end
  
  ActionController::Base.class_eval do
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    
    # Compare with #alias_method_chain, which is not available in 
    # Rails 1.1:
    alias_method :perform_action_without_newrelic_trace, :perform_action
    alias_method :perform_action, :perform_action_with_newrelic_trace
    private :perform_action
    
    #add_method_tracer :render_for_file, 'View/#{args[0]}/ForFile/Rendering'
    #add_method_tracer :render_for_text, 'View/#{newrelic_metric_path}/Text/Rendering'
    #add_method_tracer :render, 'View/#{newrelic_metric_path}/Rendering'
    
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
