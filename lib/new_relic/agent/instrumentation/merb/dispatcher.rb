require 'merb-core/dispatch/dispatcher'
# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
Merb::Request.class_eval do
  
  include NewRelic::Agent::Instrumentation::DispatcherInstrumentation

  alias_method :dispatch_without_newrelic, :handle
  alias_method :handle, :dispatch_newrelic
  def newrelic_response_code
    # Don't have an easy way to get the HTTP status from here yet
    nil
  end
end
