# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading
      class ThreadProfilingService
        attr_reader :worker_loop
        attr_accessor :worker_thread

        def initialize
          @clients = []
          @finished_clients = []

          @running = false
          @worker_loop = NewRelic::Agent::WorkerLoop.new
          @worker_thread = nil
        end

        def start
          return if @running
          @running = true
          @worker_thread = Thread.new do
            worker_loop.run(minimum_client_period, &method(:poll))
          end
        end

        def stop
          return unless @running
          @running = false
          worker_loop.stop
        end

        def minimum_client_period
          @clients.map(&:requested_period).min
        end

        def running?
          @running
        end

        def add_client(client)
          @clients << client
          start
          client
        end

        def remove_client(client)
          @clients.delete(client)
          stop if @clients.empty?
          client
        end

        def wait
          self.worker_thread.join if self.worker_thread
          self.worker_thread = nil
          stop
        end

        def each_backtrace_with_bucket
          Threading::AgentThread.list.each do |thread|
            bucket = Threading::AgentThread.bucket_thread(thread, @profile_agent_code)
            next if bucket == :ignore

            backtrace = Threading::AgentThread.scrub_backtrace(thread, @profile_agent_code)
            yield backtrace, bucket
          end
        end

        def poll
          @finished_clients += @clients.select(&:finished?)
          @clients -= @finished_clients
          stop if @clients.empty?

          each_backtrace_with_bucket do |backtrace, bucket|
            @clients.each do |client|
              client.aggregate(backtrace, bucket)
            end
          end

          adjust_worker_loop_period
        end

        def adjust_worker_loop_period
          worker_loop.period = minimum_client_period
        end

      end
    end
  end
end
