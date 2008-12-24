require 'merb-core/dispatch/dispatcher'
# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController modile 
# in rails 2.0.  Thus we need to check for both

Merb::Request.class_eval do
  
  # This is for merb prior to 1.0
  include NewRelic::Agent::Instrumentation::DispatcherInstrumentation
  alias_method :dispatch_without_newrelic, :handle
  alias_method :handle, :dispatch_newrelic
  
  # After merb 1.0, you can use before and after callbacks
  # for this?
end
