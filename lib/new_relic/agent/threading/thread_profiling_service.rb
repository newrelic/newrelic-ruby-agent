# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading
      class ThreadProfilingService
        DEFAULT_PERIOD_IN_SECONDS = 0.1
        ALL_TRANSACTIONS = "**ALL**".freeze

        attr_reader :worker_loop, :buffer
        attr_accessor :worker_thread, :profile_agent_code

        def initialize
          @profiles = {}
          @buffer = {}

          # synchronizes access to @profiles and @buffer above
          @lock = Mutex.new 

          @running = false
          @profile_agent_code = false
          @worker_loop = NewRelic::Agent::WorkerLoop.new
        end

        # Public interface

        def running?
          @running
        end

        def subscribe(transaction_name, command_arguments={})
          start
          profile = ThreadProfile.new(command_arguments)

          # Revise once X-Rays come along! They won't have the
          # profile_agent_code parameter but also shouldn't tromp if it's set
          # because of thread profiling
          self.profile_agent_code = profile.profile_agent_code

          @lock.synchronize do
            current_period = self.worker_loop.period
            self.worker_loop.period = [current_period, profile.requested_period].min
            @profiles[transaction_name] = profile
          end
        end

        def unsubscribe(transaction_name)
          @lock.synchronize do
            @profiles.delete(transaction_name)
            if @profiles.empty?
              stop
            else
              self.worker_loop.period = effective_profiling_period
            end
          end
        end

        def subscribed?(transaction_name)
          @lock.synchronize do
            @profiles.has_key?(transaction_name)
          end
        end

        def harvest(transaction_name)
          @lock.synchronize do
            if @profiles[transaction_name]
              profile = @profiles.delete(transaction_name)
              @profiles[transaction_name] = ThreadProfile.new(profile.command_arguments)
              profile
            end
          end
        end

        def on_transaction_finished(name, start, duration, options={}, thread=Thread.current)
          @lock.synchronize do
            backtraces = @buffer.delete(thread)
            if backtraces && @profiles.has_key?(name)
              end_time = start + duration
              backtraces.each do |(timestamp, backtrace)|
                if timestamp >= start && timestamp < end_time
                  @profiles[name].aggregate(backtrace, :request)
                end
              end
            end
          end
        end

        # Internals

        def start
          return if @running
          @running = true
          self.worker_thread = AgentThread.new('thread_profiling_service_worker') do
            # This default period should be immediately reset by the code at the
            # end of #subscribe above, we're using the default here to avoid
            # touching @profiles without holding the lock.
            self.worker_loop.run(DEFAULT_PERIOD_IN_SECONDS, &method(:poll))
          end
        end

        def stop
          return unless @running
          @running = false
          self.worker_loop.stop
        end

        def poll
          poll_start = Time.now

          @lock.synchronize do
            AgentThread.list.each do |thread|
              sample_thread(thread)
            end
            @profiles.values.each { |c| c.increment_poll_count }
          end

          record_polling_time(Time.now - poll_start)
        end

        # This method is expected to be called with @lock held.
        def should_buffer?(bucket)
          bucket == :request && @profiles.keys.any? { |k| k != ALL_TRANSACTIONS }
        end

        # This method is expected to be called with @lock held.
        def need_backtrace?(bucket)
          (
            bucket != :ignore &&
            (@profiles[ALL_TRANSACTIONS] || should_buffer?(bucket))
          )
        end

        # This method is expected to be called with @lock held.
        def buffer_backtrace_for_thread(thread, timestamp, backtrace, bucket)
          if should_buffer?(bucket)
            @buffer[thread] ||= []
            @buffer[thread] << [timestamp, backtrace]
          end
        end

        # This method is expected to be called with @lock held.
        def aggregate_global_backtrace(backtrace, bucket)
          if @profiles[ALL_TRANSACTIONS]
            @profiles[ALL_TRANSACTIONS].aggregate(backtrace, bucket)
          end
        end

        # This method is expected to be called with @lock held.
        def sample_thread(thread)
          bucket = AgentThread.bucket_thread(thread, @profile_agent_code)

          if need_backtrace?(bucket)
            timestamp = Time.now
            backtrace = AgentThread.scrub_backtrace(thread, @profile_agent_code)
            aggregate_global_backtrace(backtrace, bucket)
            buffer_backtrace_for_thread(thread, timestamp, backtrace, bucket)
          end
        end

        # This method is expected to be called with @lock held.
        def effective_profiling_period
          @profiles.values.map { |p| p.requested_period }.min
        end

        def record_polling_time(duration)
          NewRelic::Agent.record_metric('Supportability/ThreadProfiler/PollingTime', duration)
        end

      end
    end
  end
end
