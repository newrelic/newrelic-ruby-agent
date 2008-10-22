require 'dispatcher'


 
# We have to patch the mongrel dispatcher live since the classes
# aren't defined when our instrumentation loads
module NewRelic
  class MutexWrapper
      
    @@queue_length = 0
    
    def MutexWrapper.queue_length
      @@queue_length
    end
    
    def MutexWrapper.in_handler
      Thread.critical = true
      @@queue_length -= 1
      Thread.critical = false
    end
    
    def initialize(mutex)
      @mutex = mutex
    end
    
    def synchronize(&block)
      Thread.critical = true
      @@queue_length += 1
      Thread.critical = false
      
      Thread.current[:queue_start] = Time.now.to_f
      
      @mutex.synchronize(&block)
    end
  end
end


module NewRelicDispatcherMixIn
  
    @@mongrel = nil;
    @@patch_guard = true
  
    ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel_instance|
      @@mongrel = mongrel_instance
      @@patch_guard = false
    end
    
    @@newrelic_agent = NewRelic::Agent.agent
    @@newrelic_rails_dispatch_stat = @@newrelic_agent.stats_engine.get_stats 'Rails/HTTP Dispatch'
    @@newrelic_mongrel_queue_stat = (@@mongrel) ? @@newrelic_agent.stats_engine.get_stats('WebFrontend/Mongrel/Average Queue Time'): nil
    @@newrelic_mongrel_read_time = (@@mongrel) ? @@newrelic_agent.stats_engine.get_stats('WebFrontend/Mongrel/Average Read Time'): nil
    
    
    def patch_guard
      @@patch_guard = true

      if defined? Mongrel::Rails::RailsHandler
        handler = nil
        
        ObjectSpace.each_object(Mongrel::Rails::RailsHandler) do |handler_instance|
          # should only be one mongrel instance in the vm
          if handler
            agent.log.error("Discovered multiple Mongrel rails handler instances in one Ruby VM.  "+
              "This is unexpected and might affect the Accuracy of the Mongrel Request Queue metric.")
          end
      
          handler = handler_instance
        end
        
        if handler
          def handler.new_relic_set_guard(guard)
            @guard = guard
          end
        
          handler.new_relic_set_guard NewRelic::MutexWrapper.new(handler.guard)
          
          NewRelic::Agent.instance.stats_engine.add_sampled_metric("Mongrel/Queue Length") do |stats|
            stats.record_data_point NewRelic::MutexWrapper.queue_length
          end
        end
      end
    end
    
    
    #
    # Patch dispatch
    def dispatch_newrelic(*args)
      t0 = Time.now.to_f
      
      if !@@patch_guard
        patch_guard
        return dispatch_without_newrelic(*args)
      end
      
      
      begin
        queue_start = Thread.current[:queue_start]
        
        if queue_start
          NewRelic::MutexWrapper.in_handler
          read_start = Thread.current[:started_on]
        
          @@newrelic_mongrel_queue_stat.trace_call(t0 - queue_start)
          @@newrelic_mongrel_read_time.trace_call(queue_start - read_start.to_f) if read_start
        end
  
        @@newrelic_agent.start_transaction
        
        Thread.current[:controller_ignored] = nil
  
        begin
          result = dispatch_without_newrelic(*args)
        ensure
          @@newrelic_agent.end_transaction
          @@newrelic_rails_dispatch_stat.trace_call(Time.now.to_f - t0) if Thread.current[:controller_ignored].nil?
        end
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
