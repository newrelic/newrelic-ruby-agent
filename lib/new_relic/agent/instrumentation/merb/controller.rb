require 'set'
require 'merb-core/controller/merb_controller'

Merb::Controller.class_eval do
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation
  
  class_inheritable_accessor :newrelic_ignore_attr
  
  protected
  # determine the path that is used in the metric name for
  # the called controller action
  def newrelic_metric_path(action)
    "#{controller_name}/#{action}"
  end
  alias_method :perform_action_without_newrelic_trace, :_dispatch
  alias_method :_dispatch, :perform_action_with_newrelic_trace
end
