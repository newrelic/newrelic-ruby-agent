# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'thread'

module NewRelic
  module Agent

    # A worker loop executes a set of registered tasks on a single thread.
    # A task is a proc or block with a specified call period in seconds.
    class WorkerLoop

      attr_accessor :period, :propagate_errors
      attr_reader :iterations

      # Optional argument :duration (in seconds) for how long the worker loop runs
      # or :limit (integer) for max number of iterations
      def initialize(opts={})
        @should_run = true
        @next_invocation_time = Time.now
        @period = 60.0
        @duration = opts[:duration]
        @limit = opts[:limit]
        @iterations = 0
        @propagate_errors = opts.fetch(:propagate_errors, false)
        @deadline = nil
      end

      # Reset state that is changed by running the worker loop
      def setup(period, task)
        @task = task
        @period = period if period
        @should_run = true
        @iterations = 0

        now = Time.now
        @deadline = now + @duration if @duration
        @next_invocation_time = (now + @period)
      end

      # Run infinitely, calling the registered tasks at their specified
      # call periods.  The caller is responsible for creating the thread
      # that runs this worker loop.  This will run the task immediately.
      def run(period=nil, &block)
        setup(period, block)
        while keep_running? do
          sleep_time = schedule_next_invocation
          sleep(sleep_time) if sleep_time > 0
          run_task if keep_running?
          @iterations += 1
        end
      end

      def schedule_next_invocation
        now = Time.now
        while @next_invocation_time <= now && @period > 0
          @next_invocation_time += @period
        end
        @next_invocation_time - Time.now
      end

      # a simple accessor for @should_run
      def keep_running?
        @should_run && under_duration? && under_limit?
      end

      def under_duration?
        !@deadline || Time.now < @deadline
      end

      def under_limit?
        @limit.nil? || @iterations < @limit
      end

      # Sets @should_run to false. Returns false
      def stop
        @should_run = false
      end

      # Executes the block given to the worker loop, and handles errors.
      def run_task
        if @propagate_errors
          @task.call
        else
          begin
            @task.call
          rescue NewRelic::Agent::ForceRestartException, NewRelic::Agent::ForceDisconnectException
            # blow out the loop
            raise
          rescue => e
            # Don't blow out the stack for anything that hasn't already propagated
            ::NewRelic::Agent.logger.error "Error running task in Agent Worker Loop:", e
          end
        end
      end
    end
  end
end
