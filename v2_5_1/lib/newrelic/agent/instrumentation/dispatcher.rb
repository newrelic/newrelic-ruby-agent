require 'dispatcher'


NR_DISPATCHER_CODE_HEADER = <<-CODE

NewRelic::Agent.agent.start_transaction

if Thread.current[:started_on]
  stats = NewRelic::Agent.agent.stats_engine.get_stats 'WebFrontend/Mongrel/Average Queue Time', false
  stats.trace_call Time.now - Thread.current[:started_on]
end

CODE

# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController modile 
# in rails 2.0.  Thus we need to check for both
if defined? ActionController::Dispatcher

  class ActionController::Dispatcher

    class << self
      
      #
      # NOTE - this block is duplicated below to support rails < 2.0
      #
      
      @@newrelic_rails_dispatch_stat = NewRelic::Agent.get_stats 'Rails/HTTP Dispatch'
      @@newrelic_mongrel_queue_stat = NewRelic::Agent.get_stats 'WebFrontend/Mongrel/Average Queue Time' if defined? Mongrel::HttpServer
      
      def dispatch_newrelic(*args)
        NewRelic::Agent.agent.start_transaction
        
        Thread.current[:controller_ignored] = nil
        
        @@newrelic_mongrel_queue_stat.trace_call(Time.now - Thread.current[:started_on]) if Thread.current[:started_on]

        t0 = Time.now

        begin
          result = dispatch_without_newrelic(*args)
        ensure
          duration = Time.now - t0
          
          @@newrelic_rails_dispatch_stat.trace_call duration if Thread.current[:controller_ignored].nil?
        end
        
        result
      end
     
      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end
  
elsif defined? Dispatcher

  class Dispatcher
    class << self
      @@newrelic_rails_dispatch_stat = NewRelic::Agent.get_stats 'Rails/HTTP Dispatch'
      @@newrelic_mongrel_queue_stat = NewRelic::Agent.get_stats 'WebFrontend/Mongrel/Average Queue Time' if defined? Mongrel::HttpServer
      
      def dispatch_newrelic(*args)
        NewRelic::Agent.agent.start_transaction
        
        Thread.current[:controller_ignored] = nil
        
        @@newrelic_mongrel_queue_stat.trace_call(Time.now - Thread.current[:started_on]) if Thread.current[:started_on]

        t0 = Time.now

        begin
          result = dispatch_without_newrelic(*args)
        ensure
          duration = Time.now - t0
          
          @@newrelic_rails_dispatch_stat.trace_call duration if Thread.current[:controller_ignored].nil?
        end
        
        result
      end
     
      alias_method :dispatch_without_newrelic, :dispatch
      alias_method :dispatch, :dispatch_newrelic
    end
  end

end