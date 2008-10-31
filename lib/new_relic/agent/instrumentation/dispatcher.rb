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
      
      success = false
      begin
        @mutex.synchronize do
            MutexWrapper.in_handler
            success = true
            yield
        end
      rescue Exception => e
        MutexWrapper.in_handler if success
        raise e
      end
    end
  end
  
  class BusyCalculator
    
    # the fraction of the sample period that the dispatcher was busy
    @@instance_busy = NewRelic::Agent.agent.stats_engine.get_stats('Instance/Busy')
    @@harvest_start = Time.now.to_f
    @@accumulator = 0
    @@dispatcher_start = nil    
    def BusyCalculator.dispatcher_start(time)
      Thread.critical = true
      @@dispatcher_start = time      
      Thread.critical = false
    end
    
    def BusyCalculator.dispatcher_finish(time)
      Thread.critical = true
      
      @@accumulator += (time - @@dispatcher_start)
      @@dispatcher_start = nil
      
      Thread.critical = false
    end
    
    def BusyCalculator.add_busy(amount)
      Thread.critical = true
      @@accumulator += amount
      Thread.critical = false
    end
    
    def BusyCalculator.harvest_busy
      t0 = Time.now.to_f
      
      Thread.critical = true
      
      busy = @@accumulator
      @@accumulator = 0
      
      if @@dispatcher_start
        busy += (t0 - @@dispatcher_start)
        @@dispatcher_start = t0
      end
      
      Thread.critical = false
      
      busy = 0.0 if busy < 0.0 # don't go below 0%
      
      time_window = (t0 - @@harvest_start)
      time_window = 1.0 if time_window == 0.0  # protect against divide by zero
      
      busy = busy / time_window
      
      busy = 1.0 if busy > 1.0    # cap at 100%
            
      @@instance_busy.record_data_point busy
      
      @@harvest_start = t0
    end
    
  end
end


module NewRelicDispatcherMixIn
  
    @@mongrel = nil;
    @@patch_guard = true
  
    if defined? Mongrel
      ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel_instance|
        @@mongrel = mongrel_instance
        @@patch_guard = false
      end
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

      NewRelic::BusyCalculator.dispatcher_start t0
      
      queue_start = Thread.current[:queue_start]
      
      if queue_start
        read_start = Thread.current[:started_on]
      
        @@newrelic_mongrel_queue_stat.trace_call(t0 - queue_start)
        
        if read_start
          read_time = queue_start - read_start.to_f
          @@newrelic_mongrel_read_time.trace_call(read_time) if read_time > 0
          NewRelic::BusyCalculator.add_busy(read_time)
        end
      end

      @@newrelic_agent.start_transaction
      
      Thread.current[:controller_ignored] = nil

      begin
        result = dispatch_without_newrelic(*args)
      ensure
        t1 = Time.now.to_f
        @@newrelic_agent.end_transaction
        @@newrelic_rails_dispatch_stat.trace_call(t1 - t0) if Thread.current[:controller_ignored].nil?
        NewRelic::BusyCalculator.dispatcher_finish t1
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
