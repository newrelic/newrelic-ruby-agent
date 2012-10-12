require 'new_relic/agent/worker_loop'

module NewRelic
  module Agent
    class ThreadProfiler

      attr_reader :backtraces

      def initialize(duration)
        @duration = duration
        @backtraces = []
      end

      def run
        Thread.new do
          NewRelic::Agent::WorkerLoop.new(@duration).run(0.1) do
            Thread.list.each do |t|
              @backtraces << t.backtrace
            end
          end
        end
      end

    end 
  end
end
