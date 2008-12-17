require_dependency 'dispatcher'

# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController module 
# in rails 2.0.  Thus we need to check for both
if defined? ActionController::Dispatcher
  NewRelic::Agent.instance.log.debug "Adding ActionController::Dispatcher instrumentation"
  
  ActionController::Dispatcher.class_eval do
    class << self
      include NewRelic::DispatcherInstrumentation

      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end
elsif defined? Dispatcher
  NewRelic::Agent.instance.log.debug "Adding Dispatcher instrumentation"
  
  Dispatcher.class_eval do
    class << self
      include NewRelic::DispatcherInstrumentation

      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end
else
  NewRelic::Agent.instance.log.debug "WARNING: Dispatcher instrumentation not added"
end
