# We have to patch the mongrel dispatcher live since the classes
# aren't defined when our instrumentation loads.
# To use this module, you should monkey patch a method newrelic_response_code
# which will return the response status code when the dispatcher finishes.
module NewRelic::Agent::Instrumentation
  module DispatcherInstrumentation
    extend self
    def newrelic_dispatcher_start
      # This call might be entered twice in the same call sequence so we ignore subsequent calls.
      return if _dispatcher_start_time
      # Put the current time on the thread.  Can't put in @ivar because this could
      # be a class or instance context
      start = Time.now.to_f
      self._dispatcher_start_time = start
      BusyCalculator.dispatcher_start start
      _detect_upstream_wait
      
      NewRelic::Agent.agent.start_transaction
      
      # Reset the flag indicating the controller action should be ignored.
      # It may be set by the action to either true or false or left nil meaning false
      Thread.current[:newrelic_ignore_controller] = nil
    end
    
    def newrelic_dispatcher_finish
      NewRelic::Agent.agent.end_transaction
      return unless started = _dispatcher_start_time
      dispatcher_end_time = Time.now.to_f
      BusyCalculator.dispatcher_finish dispatcher_end_time
      unless Thread.current[:newrelic_ignore_controller]
        elapsed_time = dispatcher_end_time - started
        # Store the response header
        if response_code = newrelic_response_code 
          NewRelic::Agent.agent.stats_engine.get_stats_no_scope("HTTP/Response/#{response_code}").trace_call(elapsed_time)
        end
        # Store the response time
        _dispatch_stat.trace_call(elapsed_time)
        NewRelic::Agent.instance.histogram.process(elapsed_time)
      end
      # ensure we don't record it twice
      self._dispatcher_start_time = nil
      self._request_start_time = nil
    end
    # Should be implemented in the dispatcher class
    def newrelic_response_code; end

    def newrelic_request_headers
      self.respond_to?(:request) && self.request.respond_to?(:headers) && self.request.headers
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
    
    def _dispatcher_start_time
      Thread.current[:newrelic_dispatcher_start]
    end
    
    def _dispatcher_start_time= newval
      Thread.current[:newrelic_dispatcher_start] = newval
    end

    def _request_start_time
      Thread.current[:newrelic_request_start]
    end
    def _request_start_time=(newval)
      Thread.current[:newrelic_request_start] = newval
    end
    
    def _detect_upstream_wait
      return if _request_start_time
      # Capture the time spent in the mongrel queue, if running in mongrel.  This is the 
      # current time less the timestamp placed in 'started_on' by mongrel.
      http_entry_time = Thread.current[:started_on] and http_entry_time = http_entry_time.to_f
      
      # No mongrel.  Look for a custom header:
      if !http_entry_time && newrelic_request_headers
        entry_time = newrelic_request_headers['HTTP_X_REQUEST_START'] and
        entry_time = entry_time[/t=(\d+)/, 1 ] and 
        http_entry_time = entry_time.to_f/1e6
      end
      if http_entry_time
        self._request_start_time = http_entry_time
        queue_stat = NewRelic::Agent.agent.stats_engine.get_stats_no_scope 'WebFrontend/Mongrel/Average Queue Time'  
        queue_stat.trace_call(_dispatcher_start_time - http_entry_time)
      end
    end
    
    
    def _dispatch_stat
      NewRelic::Agent.agent.stats_engine.get_stats_no_scope 'HttpDispatcher'  
    end
    
    # This won't work with Rails 2.2 multi-threading
    module BusyCalculator
      extend self
      # the fraction of the sample period that the dispatcher was busy
      
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
      def reset
        @entrypoint_stack = []
        @lock = Mutex.new
        @accumulator = 0
        @harvest_start = Time.now.to_f
      end
      
      self.reset
      
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