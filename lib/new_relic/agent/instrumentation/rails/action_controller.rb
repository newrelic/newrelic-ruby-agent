
if defined? ActionController
  
  # Handle partial rendering in Rails 2.1 and above
  case
  when defined? ActionView::RenderablePartial # In Rails 2.2, 2.3
    ActionView::RenderablePartial.module_eval do
      add_method_tracer :render_partial, 'View/#{path}/Partial'
    end
  when defined? ActionView::PartialTemplate  # In Rails 2.1
    ActionView::PartialTemplate.module_eval do
      add_method_tracer :render, 'View/#{path}/Partial'
    end
  end
  
  # Handle Template rendering in all Rails versions
  case Rails::VERSION::STRING
    when /^(1|2\.[01])/
    ActionController::Base.class_eval do
      add_method_tracer :render, 'View/#{newrelic_metric_path}/Rendering'
    end  
    else
    ActionController::Base.class_eval do
      add_method_tracer :render_for_file, 'View/#{args[0]}/Rendering'
    end
  end
  
  # Gather the list of template handler classes
=begin  
  handler_classes = ActionView::Template.template_handler_extensions.map do | extension | 
    ActionView::Template.handler_class_for_extension(extension) 
  end.uniq
  handler_classes.each do | handler |
    handler.class_eval do
      add_method_tracer :compile, 
        'View/#{self.class.name[/[^:]*$/]}/Compile', :metric => false
    end
  end
=end
  
  # Can't seem to get a hook in this
  #ActionController::Layout.module_eval do
  #  add_method_tracer :render_with_a_layout, 'View/#{args[0]}/Layout/Rendering'
  #end
  
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
