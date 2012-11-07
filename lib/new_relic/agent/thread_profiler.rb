require 'new_relic/agent/worker_loop'

module NewRelic
  module Agent

    class ThreadProfiler

      attr_reader :profile

      def start(profile_id, duration, interval=0.1)
        NewRelic::Agent.logger.debug("Starting thread profiler")
        @profile = ThreadProfile.new(profile_id, duration, interval)
        @profile.run
      end

      def harvest
        profile = @profile
        @profile = nil
        profile
      end

      def running?
        !@profile.nil?
      end

      def finished?
        @profile && @profile.finished?
      end
    end

    class ThreadProfile

      attr_reader :profile_id, \
        :traces, :poll_count, :sample_count, \
        :start_time, :stop_time

      def initialize(profile_id, duration, interval=0.1)
        @profile_id = profile_id

        @duration = duration
        @interval = interval
        @finished = false

        @traces = {
          :agent => [],
          :background => [],
          :other => [],
          :request => []
        }
        @poll_count = 0
        @sample_count = 0
      end

      def run
        Thread.new do
          Thread.current['newrelic_label'] = 'Thread Profiler'
          @start_time = now_in_millis
          NewRelic::Agent::WorkerLoop.new(@duration).run(@interval) do
            @poll_count += 1
            Thread.list.each do |t|
              @sample_count += 1
              if t.key?('newrelic_label')
                aggregate(t.backtrace, @traces[:agent])
              else
                aggregate(t.backtrace, @traces[:request])
              end
            end
          end
          @finished = true
          @stop_time = now_in_millis
        end
      end

      def now_in_millis
        Time.now.to_f * 1_000
      end

      def finished?
        @finished
      end

      def to_compressed_array
        traces = {
          "OTHER" => @traces[:other].map{|t| t.to_array },
          "REQUEST" => @traces[:request].map{|t| t.to_array },
          "AGENT" => @traces[:agent].map{|t| t.to_array },
          "BACKGROUND" => @traces[:background].map{|t| t.to_array }
        }

        [NewRelic::Agent.config[:agent_run_id], 
          [[@profile_id,
            @start_time.to_f, @stop_time.to_f,
            @poll_count, 
            ThreadProfile.compress(JSON.dump(traces)),
            @sample_count, 0]]]
      end

      def self.compress(json)
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
          [[@file, @method, @line_no],
            @runnable_count, 0,
            @children.map {|c| c.to_array}]
        end

        def add_child(child)
          @children << child unless @children.include? child
        end
      end

    end
  end
end
