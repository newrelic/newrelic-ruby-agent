require 'thread'
module NewRelic
  module Agent
    
    # A worker loop executes a set of registered tasks on a single thread.  
    # A task is a proc or block with a specified call period in seconds.  
    class WorkerLoop
      
      attr_reader :pid
      
      def initialize
        @lock = Mutex.new
        @log = log
        @should_run = true
        @pid = $$
      end
      
      def log
        NewRelic::Control.instance.log
      end
      # Run infinitely, calling the registered tasks at their specified
      # call periods.  The caller is responsible for creating the thread
      # that runs this worker loop
      def run(period, &block)
        @period = period
        @next_invocation_time = Time.now + @period
        @task = block
        while keep_running do
          now = Time.now
          while now < @next_invocation_time
            # sleep until this next task's scheduled invocation time
            sleep_time = @next_invocation_time - now
            sleep sleep_time if sleep_time > 0
            now = Time.now
          end
          run_task if keep_running
        end
      end
      
      def keep_running
        @should_run && @pid == $$
      end
      
      def stop
        @should_run = false
      end
      
      def run_task
        @lock.synchronize do
          @task.call 
        end if keep_running
      rescue ServerError => e
        log.debug "Server Error: #{e}"
      rescue NewRelic::Agent::ForceRestartException => e
        # blow out the loop
        raise
      rescue RuntimeError => e
        # This is probably a server error which has been logged in the server along
        # with your account name.  Check and see if the agent listener is in the
        # stack trace and log it quietly if it is.
        message = "Error running task in worker loop, likely a server error (#{e})"
        if e.backtrace.grep(/agent_listener/).empty?
          log.error message
        else
          log.debug message
          log.debug e.backtrace.join("\n")
        end
      rescue Timeout::Error, NewRelic::Agent::ServerConnectionException
        # Want to ignore these because they are handled already
      rescue ScriptError, StandardError => e 
        log.error "Error running task in Agent Worker Loop '#{e}': #{e.backtrace.first}" 
        log.debug e.backtrace.join("\n")
      ensure
        while @next_invocation_time < Time.now
          @next_invocation_time += @period
        end        
      end
    end
  end
end
