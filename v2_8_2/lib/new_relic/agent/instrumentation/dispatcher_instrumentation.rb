# We have to patch the mongrel dispatcher live since the classes
# aren't defined when our instrumentation loads
module NewRelic::Agent::Instrumentation
  module DispatcherInstrumentation
    
    @@newrelic_agent = NewRelic::Agent.agent
    @@newrelic_rails_dispatch_stat = @@newrelic_agent.stats_engine.get_stats 'Rails/HTTP Dispatch'
    @@newrelic_mongrel_queue_stat = @@newrelic_agent.stats_engine.get_stats('WebFrontend/Mongrel/Average Queue Time')
    
    def newrelic_dispatcher_start
      # Put the current time on the thread.  Can't put in @ivar because this could
      # be a class or instance context
      t0 = Time.now.to_f
      NewRelic::Config.instance.log.warn "Recursive entry into dispatcher_start!\n#{caller.join("\n   ")}" if Thread.current[:newrelic_t0]
      Thread.current[:newrelic_t0] = t0
      NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.dispatcher_start t0
      # capture the time spent in the mongrel queue, if running in mongrel.  This is the 
      # current time less the timestamp placed in 'started_on' by mongrel. 
      mongrel_start = Thread.current[:started_on]
      @@newrelic_mongrel_queue_stat.trace_call(t0 - mongrel_start.to_f) if mongrel_start
      @@newrelic_agent.start_transaction
      
      # Reset the flag indicating the controller action should be ignored.
      # It may be set by the action to either true or false or left nil meaning false
      Thread.current[:controller_ignored] = nil
    end
    
    def newrelic_dispatcher_finish
      t0 = Thread.current[:newrelic_t0]
      if t0.nil?
        NewRelic::Config.instance.log.warn "Dispatcher finish called twice!\n#{caller.join("\n   ")}" 
        return
      end
      t1 = Time.now.to_f
      @@newrelic_agent.end_transaction
      @@newrelic_rails_dispatch_stat.trace_call(t1 - t0) unless Thread.current[:controller_ignored]
      NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.dispatcher_finish t1    
      Thread.current[:newrelic_t0] = nil
    end
    
    def dispatch_newrelic(*args)
      newrelic_dispatcher_start
      begin
        dispatch_without_newrelic(*args)
      ensure
        newrelic_dispatcher_finish
      end
    end
    
    # This won't work with Rails 2.2 multi-threading
    module BusyCalculator
      extend self
      # the fraction of the sample period that the dispatcher was busy
      @instance_busy = NewRelic::Agent.agent.stats_engine.get_stats('Instance/Busy')
      @harvest_start = Time.now.to_f
      @accumulator = 0
      @dispatcher_start = nil    
      def dispatcher_start(time)
        Thread.critical = true
        @dispatcher_start = time      
        Thread.critical = false
      end
      
      def dispatcher_finish(time)
        Thread.critical = true
        @accumulator += (time - @dispatcher_start)
        @dispatcher_start = nil
        
        Thread.critical = false
      end
      
      def is_busy?
        @dispatcher_start
      end
      
      def harvest_busy
        Thread.critical = true
        
        busy = @accumulator
        @accumulator = 0
        
        t0 = Time.now.to_f
        
        if @dispatcher_start
          busy += (t0 - @dispatcher_start)
          @dispatcher_start = t0
        end
        
        
        Thread.critical = false
        
        busy = 0.0 if busy < 0.0 # don't go below 0%
        
        time_window = (t0 - @harvest_start)
        time_window = 1.0 if time_window == 0.0  # protect against divide by zero
        
        busy = busy / time_window
        
        busy = 1.0 if busy > 1.0    # cap at 100%
        @instance_busy.record_data_point busy
        @harvest_start = t0
      end
    end
  end
end