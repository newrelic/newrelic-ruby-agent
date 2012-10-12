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

      def self.aggregate(trace, call_tree={})
        return {} if trace.empty?
        if call_tree[trace.last]
          call_tree[trace.last][:runnable_count] += 1
          call_tree[trace.last][:children].merge!(
            aggregate(trace[0..-2],
            call_tree[trace.last][:children])
          )
        else
          call_tree[trace.last] = { :runnable_count => 1, :children => aggregate(trace[0..-2]) }
        end
        call_tree
      end

      def self.parse_backtrace(trace)
        trace.map do |line|
          line =~ /(.*)\:(\d+)\:in `(.*)'/
          { :method => $3, :line_no => $2.to_i, :file => $1 }
        end
      end

    end 
  end
end
