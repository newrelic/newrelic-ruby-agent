require 'dispatcher'
# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController module 
# in Rails 2.0.  Thus we need to check for both
if defined? ActionController::Dispatcher
  target = ActionController::Dispatcher
elsif defined? Dispatcher
  target = Dispatcher
end

# NOTE TODO: maybe this should be done with a middleware?
if target
  require 'action_pack/version'
  NewRelic::Agent.instance.log.debug "Adding #{target} instrumentation"
  
  target.class_eval do
    if ActionPack::VERSION::MAJOR >= 2
      # In versions later that 1.* the dispatcher callbacks are used
      include NewRelic::Agent::Instrumentation::DispatcherInstrumentation
      before_dispatch :newrelic_dispatcher_start
      after_dispatch :newrelic_dispatcher_finish
      def newrelic_response_code
        (@response.headers['Status']||'200')[0..2] if ActionPack::VERSION::MAJOR == 2 && ActionPack::VERSION::MINOR < 3 
      end
    else
      # In version 1.2.* the instrumentation is done by method chaining
      # the static dispatch method on the dispatcher class
      extend NewRelic::Agent::Instrumentation::DispatcherInstrumentation
      class << self
        alias_method :dispatch_without_newrelic, :dispatch
        alias_method :dispatch, :dispatch_newrelic
        def newrelic_response_code; end
      end
    end
  end
else
  NewRelic::Agent.instance.log.debug "WARNING: Dispatcher instrumentation not added"
end
