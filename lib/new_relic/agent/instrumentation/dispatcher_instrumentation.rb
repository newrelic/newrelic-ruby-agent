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
      #puts @env.to_a.map{|k,v| "#{'%32s' % k}: #{v.inspect[0..64]}"}.join("\n")
      dispatcher_end_time = Time.now.to_f
      NewRelic::Agent.agent.end_transaction
      NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.dispatcher_finish dispatcher_end_time
      unless Thread.current[:controller_ignored]
        # Store the response header
        newrelic_dispatcher_start_time = Thread.current[:newrelic_dispatcher_start]
        response_code = newrelic_response_code
        if response_code
          stats = NewRelic::Agent.agent.stats_engine.get_stats_no_scope("HTTP/Response/#{response_code}")
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
    
    private
    # memoize the stats to avoid the cost of the lookup each time.
    def dispatch_stat
      NewRelic::Agent.agent.stats_engine.get_stats_no_scope 'Rails/HTTP Dispatch'  
    end
    def mongrel_queue_stat
      NewRelic::Agent.agent.stats_engine.get_stats_no_scope 'WebFrontend/Mongrel/Average Queue Time'  
    end
    
    # This won't work with Rails 2.2 multi-threading
    module BusyCalculator
      extend self
      # the fraction of the sample period that the dispatcher was busy
      
      @harvest_start = Time.now.to_f
      @accumulator = 0
      @entrypoint_stack = []
      @lock = Mutex.new
      
      def dispatcher_start(time)
        @lock.synchronize do
          @entrypoint_stack.push time      
        end
      end
      
      def dispatcher_finish(time)
        @lock.synchronize do
          NewRelic::Control.instance.log.error("Stack underflow tracking dispatcher entry and exit!\n  #{caller.join("  \n")}") and return if @entrypoint_stack.empty?
          @accumulator += (time - @entrypoint_stack.pop)
        end
      end
      
      def busy_count
        @entrypoint_stack.size
      end

      # Called before uploading to to the server to collect current busy stats.
      def harvest_busy
        busy = 0
        t0 = Time.now.to_f
        @lock.synchronize do
          busy = @accumulator
          @accumulator = 0
          
          # Walk through the stack and capture all times up to 
          # now for entrypoints
          @entrypoint_stack.size.times do |frame| 
            busy += (t0 - @entrypoint_stack[frame])
            @entrypoint_stack[frame] = t0
          end
          
        end
        
        busy = 0.0 if busy < 0.0 # don't go below 0%
        
        time_window = (t0 - @harvest_start)
        time_window = 1.0 if time_window == 0.0  # protect against divide by zero
        
        busy = busy / time_window
        
        instance_busy_stats.record_data_point busy unless busy == 0
        @harvest_start = t0
      end
      private
      def instance_busy_stats
        # Late binding on the Instance/busy stats
        NewRelic::Agent.agent.stats_engine.get_stats_no_scope 'Instance/Busy'  
      end
      
    end
    
  end
end