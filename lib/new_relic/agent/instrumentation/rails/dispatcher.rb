require 'dispatcher'

# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController module 
# in Rails 2.0.  Thus we need to check for both
if defined? ActionController::Dispatcher
  target = ActionController::Dispatcher
elsif defined? Dispatcher
  target = Dispatcher
else
  target = nil
end

if target
  NewRelic::Agent.instance.log.debug "Adding #{target} instrumentation"
  
  # in Rails 2.3 (Rack-based) we don't want to add instrumentation on class level
  unless defined? ::Rails::Rack
    target = target.class_eval { class << self; self; end }
  end
  
  target.class_eval do
    include NewRelic::Agent::Instrumentation::DispatcherInstrumentation

    alias_method :dispatch_without_newrelic, :dispatch
    alias_method :dispatch, :dispatch_newrelic
  end
else
  NewRelic::Agent.instance.log.debug "WARNING: Dispatcher instrumentation not added"
end
