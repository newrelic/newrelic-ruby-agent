# We have to patch the mongrel dispatcher live since the classes
# aren't defined when our instrumentation loads
# To use this module, you need to monkey patch a method newrelic_response_code
# which will return the response status code when the dispatcher finishes.
module NewRelic::Agent::Instrumentation
  module DispatcherInstrumentation
    
    def newrelic_dispatcher_start
      # Put the current time on the thread.  Can't put in @ivar because this could
      # be a class or instance context
      newrelic_dispatcher_start_time = Time.now.to_f
      Thread.current[:newrelic_dispatcher_start] = newrelic_dispatcher_start_time
      NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.dispatcher_start newrelic_dispatcher_start_time
      # capture the time spent in the mongrel queue, if running in mongrel.  This is the 
      # current time less the timestamp placed in 'started_on' by mongrel. 
      mongrel_start = Thread.current[:started_on]
      mongrel_queue_stat.trace_call(newrelic_dispatcher_start_time - mongrel_start.to_f) if mongrel_start
      NewRelic::Agent.agent.start_transaction
      
      # Reset the flag indicating the controller action should be ignored.
      # It may be set by the action to either true or false or left nil meaning false
      Thread.current[:controller_ignored] = nil
    end
    
    def newrelic_dispatcher_finish
      dispatcher_end_time = Time.now.to_f
      NewRelic::Agent.agent.end_transaction
      NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.dispatcher_finish dispatcher_end_time
      unless Thread.current[:controller_ignored]
        # Store the response header
        newrelic_dispatcher_start_time = Thread.current[:newrelic_dispatcher_start]
        response_code = newrelic_response_code
        if response_code
          stats = response_stats[response_code] ||= NewRelic::Agent.agent.stats_engine.get_stats("HTTP/Response/#{response_code}")
          stats.trace_call(dispatcher_end_time - newrelic_dispatcher_start_time)
        end
        dispatch_stat.trace_call(dispatcher_end_time - newrelic_dispatcher_start_time) 
      end
    end
    def newrelic_response_code
      raise "Must be implemented in the dispatcher class"
    end
    # Used only when no before/after callbacks are available with
    # the dispatcher, such as Rails before 2.0
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
      
      @harvest_start = Time.now.to_f
      @accumulator = 0
      @entrypoint_stack = []    
      
      def dispatcher_start(time)
        Thread.critical = true
        @entrypoint_stack.push time      
        Thread.critical = false
      end
      
      def dispatcher_finish(time)
        NewRelic::Control.instance.log.error "Stack underflow tracking dispatcher entry and exit!\n  #{caller.join("  \n")}" if @entrypoint_stack.empty?
        Thread.critical = true
        @accumulator += (time - @entrypoint_stack.pop)
        Thread.critical = false
      end
      
      def busy_count
        @entrypoint_stack.size
      end
      
      def harvest_busy
        Thread.critical = true
        
        busy = @accumulator
        @accumulator = 0
        
        t0 = Time.now.to_f

        # Walk through the stack and capture all times up to 
        # now for entrypoints
        @entrypoint_stack.size.times do |frame| 
          busy += (t0 - @entrypoint_stack[frame])
          @entrypoint_stack[frame] = t0
        end
        
        
        Thread.critical = false
        
        busy = 0.0 if busy < 0.0 # don't go below 0%
        
        time_window = (t0 - @harvest_start)
        time_window = 1.0 if time_window == 0.0  # protect against divide by zero
        
        busy = busy / time_window
        
        busy = 1.0 if busy > 1.0    # cap at 100%
        instance_busy_stats.record_data_point busy
        @harvest_start = t0
      end
      private
      def instance_busy_stats
        # Late binding on the Instance/busy stats
        @instance_busy ||= NewRelic::Agent.agent.stats_engine.get_stats('Instance/Busy')  
      end
      
    end
    
    private
    # memoize the stats to avoid the cost of the lookup each time.
    def dispatch_stat
      @@newrelic_rails_dispatch_stat ||= NewRelic::Agent.agent.stats_engine.get_stats 'Rails/HTTP Dispatch'  
    end
    def mongrel_queue_stat
      @@newrelic_mongrel_queue_stat ||= NewRelic::Agent.agent.stats_engine.get_stats('WebFrontend/Mongrel/Average Queue Time')  
    end
    def response_stats
      @@newrelic_response_stats ||= { '200' => NewRelic::Agent.agent.stats_engine.get_stats('HTTP/Response/200')}  
    end
    
  end
end