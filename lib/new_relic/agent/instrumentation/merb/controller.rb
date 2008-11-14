require 'set'
require 'merb-core/controller/abstract_controller'

Merb::AbstractController.class_eval do
  include ControllerInstrumentation::InstanceMethods
  class << self
    include ControllerInstrumentation::ClassMethods
  end
  
  protected
  # determine the path that is used in the metric name for
  # the called controller action
  def _determine_metric_path(action)
    "#{controller_name}/#{action}"
  end
  alias_method :perform_action_without_newrelic_trace, :_dispatch
  alias_method :_dispatch, :perform_action_with_newrelic_trace
end
