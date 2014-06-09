# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_state'

module NewRelic
  module Agent
    # This module supports calculation of actual time spent processing requests over the course of
    # one harvest period.  It's similar to what you would get if you just added up all the
    # execution times of controller calls, however that will be inaccurate when requests
    # span the minute boundaries.  This module manages accounting of requests not yet
    # completed.
    #
    # Calls are re-entrant.  All start calls must be paired with finish
    # calls, or a reset call.
    module BusyCalculator

      extend self

      # For testability, add accessors:
      attr_reader :harvest_start, :accumulator

      # sets up busy calculations based on the start and end of
      # transactions - used for a rough estimate of what percentage of
      # wall clock time is spent processing requests
      def dispatcher_start(time) #THREAD_LOCAL_ACCESS
        state = TransactionState.tl_get
        state.busy_entries ||= 0
        callers = state.busy_entries += 1
        return if callers > 1
        @lock.synchronize do
          @entrypoint_stack.push time
        end
      end

      # called when a transaction finishes, to add time to the
      # instance variable accumulator. this is harvested when we send
      # data to the server
      def dispatcher_finish(end_time = nil) #THREAD_LOCAL_ACCESS
        state = TransactionState.tl_get
        # If #dispatcher_start hasn't been called at least once, abort early
        return unless state.busy_entries

        end_time ||= time_now
        callers = state.busy_entries -= 1

        # Ignore nested calls
        return if callers > 0

        @lock.synchronize do
          if @entrypoint_stack.empty?
            ::NewRelic::Agent.logger.warn("Stack underflow tracking dispatcher entry and exit!\n  #{caller.join("  \n")}")
          else
            @accumulator += (end_time - @entrypoint_stack.pop).to_f
          end
        end
      end

      # this returns the size of the entry point stack, which
      # determines how many transactions are running
      def busy_count
        @entrypoint_stack.size
      end

      # Reset the state of the information accumulated by all threads,
      # but only reset the recursion counter for this thread.
      def reset #THREAD_LOCAL_ACCESS
        @entrypoint_stack = []
        TransactionState.tl_get.busy_entries = 0
        @lock ||= Mutex.new
        @accumulator = 0
        @harvest_start = time_now
      end


      # Called before uploading to to the server to collect current busy stats.
      def harvest_busy
        busy = 0
        t0 = time_now
        @lock.synchronize do
          busy = accumulator
          @accumulator = 0

          # Walk through the stack and capture all times up to
          # now for entrypoints
          @entrypoint_stack.size.times do |frame|
            busy += (t0 - @entrypoint_stack[frame]).to_f
            @entrypoint_stack[frame] = t0
          end

        end

        busy = 0.0 if busy < 0.0 # don't go below 0%

        time_window = (t0 - harvest_start).to_f
        time_window = 1.0 if time_window == 0.0  # protect against divide by zero

        busy = busy / time_window

        if Agent.config[:report_instance_busy]
          NewRelic::Agent.record_metric('Instance/Busy', busy)
        end
        @harvest_start = t0
      end

      private

      # so we can stub Time.now only for the BusyCalculator in tests
      def time_now
        Time.now
      end

      self.reset
    end
  end
end
