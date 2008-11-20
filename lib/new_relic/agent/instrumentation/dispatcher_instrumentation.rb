#require_dependency 'dispatcher'

# We have to patch the mongrel dispatcher live since the classes
# aren't defined when our instrumentation loads
module NewRelic::DispatcherInstrumentation
  
  @@mongrel = nil;
  
  if defined? Mongrel
    ObjectSpace.each_object(Mongrel::HttpServer) do |mongrel_instance|
      @@mongrel = mongrel_instance
    end
  end
  
  @@newrelic_agent = NewRelic::Agent.agent
  @@newrelic_rails_dispatch_stat = @@newrelic_agent.stats_engine.get_stats 'Rails/HTTP Dispatch'
  @@newrelic_mongrel_queue_stat = (@@mongrel) ? @@newrelic_agent.stats_engine.get_stats('WebFrontend/Mongrel/Average Queue Time'): nil
  
  def dispatcher_start
    # Put the current time on the thread.  Can't put in @ivar because this could
    # be a class or instance context
    t0 = Time.now.to_f
    Thread.current[:newrelic_t0] = t0
    NewRelic::DispatcherInstrumentation::BusyCalculator.dispatcher_start t0
    # capture the time spent in the mongrel queue, if running in mongrel.  This is the 
    # current time less the timestamp placed in 'started_on' by mongrel. 
    mongrel_start = Thread.current[:started_on]
    @@newrelic_mongrel_queue_stat.trace_call(t0 - mongrel_start.to_f) if mongrel_start
    @@newrelic_agent.start_transaction
    
    # Reset the flag indicating the controller action should be ignored.
    # It may be set by the action.
    Thread.current[:controller_ignored] = nil
  end
  
  def dispatcher_finish
    t0 = Thread.current[:newrelic_t0] or return
    t1 = Time.now.to_f
    @@newrelic_agent.end_transaction
    @@newrelic_rails_dispatch_stat.trace_call(t1 - t0) unless Thread.current[:controller_ignored]
    NewRelic::DispatcherInstrumentation::BusyCalculator.dispatcher_finish t1    
  end
  
  def dispatch_newrelic(*args)
    dispatcher_start
    begin
      dispatch_without_newrelic(*args)
    ensure
      dispatcher_finish
    end
  end
  
  # This won't work with Rails 2.2 multi-threading
  class BusyCalculator
    
    # the fraction of the sample period that the dispatcher was busy
    @@instance_busy = NewRelic::Agent.agent.stats_engine.get_stats('Instance/Busy')
    @@harvest_start = Time.now.to_f
    @@accumulator = 0
    @@dispatcher_start = nil    
    def self.dispatcher_start(time)
      Thread.critical = true
      @@dispatcher_start = time      
      Thread.critical = false
    end
    
    def self.dispatcher_finish(time)
      Thread.critical = true
      
      @@accumulator += (time - @@dispatcher_start)
      @@dispatcher_start = nil
      
      Thread.critical = false
    end
    
    def self.is_busy?
      @@dispatcher_start
    end
    
    def self.harvest_busy
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