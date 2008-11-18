require_dependency 'dispatcher'

# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController modile 
# in rails 2.0.  Thus we need to check for both
if defined? ActionController::Dispatcher
  ActionController::Dispatcher.class_eval do
    class << self
      include NewRelic::DispatcherInstrumentation

      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end
elsif defined? Dispatcher
  Dispatcher.class_eval do
    class << self
      include NewRelic::DispatcherInstrumentation

      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end
end
