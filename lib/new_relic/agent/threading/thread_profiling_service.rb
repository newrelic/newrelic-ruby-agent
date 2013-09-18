# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading
      class ThreadProfilingService
        ALL_TRANSACTIONS = "**ALL**".freeze

        attr_reader :worker_loop
        attr_accessor :worker_thread, :profile_agent_code

        def initialize
          @profiles = {}

          @running = false
          @profile_agent_code = false
          @worker_loop = NewRelic::Agent::WorkerLoop.new
        end

        def start
          return if @running
          @running = true
          self.worker_thread = AgentThread.new('thread_profiling_service_worker') do
            self.worker_loop.run(effective_profiling_period, &method(:poll))
          end
        end

        def stop
          return unless @running
          @running = false
          self.worker_loop.stop
        end

        def effective_profiling_period
          @profiles.values.map { |p| p.requested_period }.min
        end

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

          current_period = self.worker_loop.period
          self.worker_loop.period = [current_period, profile.requested_period].min

          @profiles[transaction_name] = profile
        end

        def unsubscribe(transaction_name)
          @profiles.delete(transaction_name)
          if @profiles.empty?
            stop
          else
            self.worker_loop.period = effective_profiling_period
          end
        end

        def subscribed?(transaction_name)
          @profiles.has_key?(transaction_name)
        end

        def harvest(transaction_name)
          if @profiles[transaction_name]
            profile = @profiles.delete(transaction_name)
            @profiles[transaction_name] = ThreadProfile.new(profile.command_arguments)
            profile
          end
        end

        def each_backtrace_with_bucket
          AgentThread.list.each do |thread|
            bucket = Threading::AgentThread.bucket_thread(thread, @profile_agent_code)
            next if bucket == :ignore

            backtrace = Threading::AgentThread.scrub_backtrace(thread, @profile_agent_code)
            yield backtrace, bucket
          end
        end

        def poll
          poll_start = Time.now

          each_backtrace_with_bucket do |backtrace, bucket|
            if @profiles[ALL_TRANSACTIONS]
              @profiles[ALL_TRANSACTIONS].aggregate(backtrace, bucket)
            end
          end

          @profiles.values.each { |c| c.increment_poll_count }
          record_polling_time(Time.now - poll_start)
        end

        def record_polling_time(duration)
          NewRelic::Agent.record_metric('Supportability/ThreadProfiler/PollingTime', duration)
        end

      end
    end
  end
end
