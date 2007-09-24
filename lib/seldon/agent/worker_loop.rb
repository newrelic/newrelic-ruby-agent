require 'thread'

# The worker loop executes a set of registered tasks.  A task is a proc or block with a specified
# call period in seconds.
module Seldon::Agent
  class WorkerLoop
    attr_reader :log
    
    def initialize(log = Logger.new(STDOUT))
      @tasks = []
      @mutex = Mutex.new
      @log = log
    end
    
    def run
      while(true) do
        run_next_task
      end
    end

    def run_next_task
      return if @tasks.empty?
      
      # get the next task to be executed, which is the task with the lowest (ie, soonest)
      # next invocation time.
      task = get_next_task

      # super defensive, shouldn't happen if we have a non-empty task list
      if task.nil?
        sleep 5.0
        return
      end
      
      # sleep until this next task's scheduled invocation time
      sleep_time = task.next_invocation_time - Time.now
      sleep sleep_time unless sleep_time <= 0
      
      begin
        task.execute
      rescue Exception => e
        log.error "Error running task in Agent Worker Loop: #{e}" 
        log.debug e.backtrace.to_s
      end
    end
    
    MIN_CALL_PERIOD = 0.1
    def add_task(call_period, &task_proc)
      if call_period <MIN_CALL_PERIOD
        raise ArgumentError.new("Invalid Call Period (must be > #{MIN_CALL_PERIOD}): #{call_period}") 
      end
      
      @mutex.synchronize do 
        @tasks << LoopTask.new(call_period, &task_proc)
      end
    end
      
    private 
      def get_next_task
        @mutex.synchronize do
          return @tasks.inject do |soonest, task|
            (task.next_invocation_time < soonest.next_invocation_time) ? task : soonest
          end
        end
      end
    
      class LoopTask
      
        def initialize(call_period, &task_proc)
          @call_period = call_period
          @last_invocation_time = Time.now
          @task = task_proc
        end
      
        def next_invocation_time
          @last_invocation_time + @call_period
        end
      
        def execute
          @last_invocation_time = Time.now
          @task.call
        end
      end
  end
end
