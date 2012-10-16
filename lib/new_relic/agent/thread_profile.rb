require 'new_relic/agent/worker_loop'

module NewRelic
  module Agent
    class ThreadProfile

      attr_reader :traces, :poll_count, :sample_count

      def initialize(profile_id, duration)
        @profile_id = profile_id
        @duration = duration
        @traces = {
          :request => []
        }
        @poll_count = 0
        @sample_count = 0
      end

      def run
        Thread.new do
          NewRelic::Agent::WorkerLoop.new(@duration).run(0.1) do
            @poll_count += 1
            Thread.list.each do |t|
              @sample_count += 1
              # TODO: Put each thread into the right bucket's aggregate...
            end
          end
        end
      end

      def to_compressed_array
        traces = {"REQUEST" => @traces[:request].map{|t| t.to_array }}
        compressed = block_given? ? yield(traces) : compress(traces)

        [NewRelic::Agent.config[:agent_run_id], 
          [[@profile_id,
            @start_time, 
            @stop_time, @poll_count, 
            compressed,
            @sample_count, 0]]]
      end

      def compress(traces)
        json = JSON.dump(traces)
        compressed = Base64.encode64(Zlib::Deflate.deflate(json, Zlib::DEFAULT_COMPRESSION))
      end

      def aggregate(trace, trees=@traces[:request], parent=nil)
        return nil if trace.empty?
        node = Node.new(trace.last)
        existing = trees.find {|n| n == node} || node

        if parent
          parent.add_child(node)
        else
          trees << node unless trees.include? node
        end

        existing.runnable_count += 1
        aggregate(trace[0..-2], existing.children, existing)
        
        existing
      end

      def self.parse_backtrace(trace)
        trace.map do |line|
          line =~ /(.*)\:(\d+)\:in `(.*)'/
          { :method => $3, :line_no => $2.to_i, :file => $1 }
        end
      end

      class Node
        attr_reader :file, :method, :line_no, :children
        attr_accessor :runnable_count

        def initialize(line, parent=nil)
          line =~ /(.*)\:(\d+)\:in `(.*)'/
          @file = $1
          @method = $3
          @line_no = $2.to_i
          @children = []
          @runnable_count = 0

          parent.add_child(self) if parent
        end

        def ==(other)
          @file == other.file &&
            @method == other.method &&
            @line_no == other.line_no
        end

        def to_array
          [[@file, @method, @line_no], 1, 0,
            @children.map {|c| c.to_array}]
        end

        def add_child(child)
          @children << child unless @children.include? child
        end
      end

    end
  end
end
