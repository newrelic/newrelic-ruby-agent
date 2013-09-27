# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading
      class BacktraceService
        ALL_TRANSACTIONS = "**ALL**".freeze

        attr_reader :worker_loop, :buffer
        attr_accessor :worker_thread, :profile_agent_code

        def initialize(event_listener=nil)
          @profiles = {}
          @buffer = {}

          # synchronizes access to @profiles and @buffer above
          @lock = Mutex.new

          @running = false
          @profile_agent_code = false
          @worker_loop = NewRelic::Agent::WorkerLoop.new

          if event_listener
            event_listener.subscribe(:transaction_finished, &method(:on_transaction_finished))
          end
        end

        # Public interface

        def running?
          @running
        end

        def subscribe(transaction_name, command_arguments={})
          NewRelic::Agent.logger.debug("Backtrace Service subscribing transaction '#{transaction_name}'")

          profile = ThreadProfile.new(command_arguments)

          @lock.synchronize do
            @profiles[transaction_name] = profile
            update_values_from_profiles
          end

          start
          profile
        end

        def unsubscribe(transaction_name)
          NewRelic::Agent.logger.debug("Backtrace Service unsubscribing transaction '#{transaction_name}'")
          @lock.synchronize do
            @profiles.delete(transaction_name)
            if @profiles.empty?
              stop
            else
              update_values_from_profiles
            end
          end
        end

        def update_values_from_profiles
          self.worker_loop.period = effective_profiling_period
          self.profile_agent_code = should_profile_agent_code?
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
              profile.finished_at = Time.now
              @profiles[transaction_name] = ThreadProfile.new(profile.command_arguments)
              profile
            end
          end
        end

        def on_transaction_finished(name, start, duration, options={}, thread=Thread.current)
          @lock.synchronize do
            backtraces = @buffer.delete(thread)
            if backtraces && @profiles.has_key?(name)
              aggregate_backtraces(backtraces, name, start, duration)
            end
          end
        end

        # Internals

        # This method is expected to be called with @lock held.
        def aggregate_backtraces(backtraces, name, start, duration)
          end_time = start + duration
          backtraces.each do |(timestamp, backtrace)|
            if timestamp >= start && timestamp < end_time
              @profiles[name].aggregate(backtrace, :request)
            end
          end
        end

        def start
          return if @running
          @running = true
          self.worker_thread = AgentThread.new('Backtrace Service') do
            begin
              # Not passing period because we expect it's already been set.
              self.worker_loop.run(&method(:poll))
            ensure
              NewRelic::Agent.logger.debug("Exiting New Relic thread: Backtrace Service")
            end
          end
        end

        def stop
          return unless @running
          @running = false
          self.worker_loop.stop
        end

        def wait
          return unless @running && @worker_thread
          @worker_thread.join
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
        attr_reader :profiles

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

        MAX_BUFFER_LENGTH = 500

        # This method is expected to be called with @lock held.
        def buffer_backtrace_for_thread(thread, timestamp, backtrace, bucket)
          if should_buffer?(bucket)
            @buffer[thread] ||= []
            if @buffer[thread].length < MAX_BUFFER_LENGTH
              @buffer[thread] << [timestamp, backtrace]
            end
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
            timestamp = Time.now.to_f
            backtrace = AgentThread.scrub_backtrace(thread, @profile_agent_code)
            aggregate_global_backtrace(backtrace, bucket)
            buffer_backtrace_for_thread(thread, timestamp, backtrace, bucket)
          end
        end

        # This method is expected to be called with @lock held.
        def effective_profiling_period
          @profiles.values.map { |p| p.requested_period }.min
        end

        # This method is expected to be called with @lock held.
        def should_profile_agent_code?
          @profiles.values.any? { |p| p.profile_agent_code }
        end

        def record_polling_time(duration)
          NewRelic::Agent.record_metric('Supportability/ThreadProfiler/PollingTime', duration)
        end

      end
    end
  end
end
