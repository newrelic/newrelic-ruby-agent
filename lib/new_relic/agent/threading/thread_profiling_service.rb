# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading
      class ThreadProfilingService
        attr_reader :worker_loop, :clients
        attr_accessor :worker_thread, :profile_agent_code

        def initialize
          @clients = []
          @clients_lock = Mutex.new

          @running = false
          @profile_agent_code = false
          @worker_loop = NewRelic::Agent::WorkerLoop.new
          @worker_thread = nil
        end

        def start
          return if @running
          @running = true
          @worker_thread = AgentThread.new('thread_profiling_service_worker') do
            self.worker_loop.run(minimum_client_period, &method(:poll))
          end
        end

        def stop
          return unless @running
          @running = false
          self.worker_loop.stop
        end

        def minimum_client_period
          @clients_lock.synchronize do
            @clients.map(&:requested_period).min
          end
        end

        def running?
          @running
        end

        def add_client(client)
          @clients_lock.synchronize do
            @clients << client
          end

          start
          client
        end

        def wait
          self.worker_thread.join if self.worker_thread
          self.worker_thread = nil
          stop
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

          @clients_lock.synchronize do
            @clients.reject!(&:finished?)

            if @clients.empty?
              stop
              return
            end

            each_backtrace_with_bucket do |backtrace, bucket|
              @clients.each do |client|
                client.aggregate(backtrace, bucket)
              end
            end

            @clients.each(&:increment_poll_count)
          end

          self.worker_loop.period = minimum_client_period
          record_polling_time(Time.now - poll_start)
        end

        def record_polling_time(duration)
          NewRelic::Agent.record_metric('Supportability/ThreadProfiler/PollingTime', duration)
        end

      end
    end
  end
end
