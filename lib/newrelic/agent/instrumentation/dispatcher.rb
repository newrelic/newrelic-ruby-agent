require 'dispatcher'



module NewRelicDispatcherMixIn
    @@newrelic_agent = NewRelic::Agent.agent
    @@newrelic_rails_dispatch_stat = @@newrelic_agent.stats_engine.get_stats 'Rails/HTTP Dispatch'
    @@newrelic_mongrel_queue_stat = defined?(Mongrel::HttpServer) ?
       @@newrelic_agent.stats_engine.get_stats('WebFrontend/Mongrel/Average Queue Time'): nil 
    
    def dispatch_newrelic(*args)
      @@newrelic_agent.start_transaction
      
      Thread.current[:controller_ignored] = nil
      
      t0 = Time.now.to_f

      @@newrelic_mongrel_queue_stat.trace_call(t0 - Thread.current[:started_on].to_f) if (Thread.current[:started_on] && @@newrelic_mongrel_queue_stat) 

      begin
        result = dispatch_without_newrelic(*args)
      ensure
        @@newrelic_rails_dispatch_stat.trace_call(Time.now.to_f - t0) if Thread.current[:controller_ignored].nil?
      end
      
      result
    end
end



# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController modile 
# in rails 2.0.  Thus we need to check for both
if defined? ActionController::Dispatcher
  class ActionController::Dispatcher
    class << self
      include NewRelicDispatcherMixIn

      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end
elsif defined? Dispatcher
  class Dispatcher
    class << self
      include NewRelicDispatcherMixIn

      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end
end
