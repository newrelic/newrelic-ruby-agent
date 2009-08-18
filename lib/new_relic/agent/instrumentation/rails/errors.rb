
ActionController::Base.class_eval do
  
  # Make a note of an exception associated with the currently executin
  # controller action.
  def newrelic_notice_error(exception, custom_params = {})
    filtered_params = (respond_to? :filter_parameters) ? filter_parameters(params) : params
    filtered_params.merge!(custom_params)
    NewRelic::Agent.agent.error_collector.notice_error(exception, request, newrelic_metric_path, filtered_params)
  end
  
  def rescue_action_with_newrelic_trace(exception)
    newrelic_notice_error exception
    
    rescue_action_without_newrelic_trace exception
  end
  
  # Compare with #alias_method_chain, which is not available in 
  # Rails 1.1:
  alias_method :rescue_action_without_newrelic_trace, :rescue_action
  alias_method :rescue_action, :rescue_action_with_newrelic_trace
  protected :rescue_action

end if defined? ActionController

Object.send :include, NewRelic::Agent::Instrumentation::ErrorInstrumentation
