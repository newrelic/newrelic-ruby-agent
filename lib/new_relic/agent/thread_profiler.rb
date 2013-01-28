require 'new_relic/agent/thread'
require 'new_relic/agent/worker_loop'

module NewRelic
  module Agent

    class ThreadProfiler

      attr_reader :profile

      def self.is_supported?
        RUBY_VERSION >= "1.9.2"
      end

      def start(profile_id, duration, interval, profile_agent_code)
        if !ThreadProfiler.is_supported?
          ::NewRelic::Agent.logger.debug("Not starting thread profile as it isn't supported on this environment")
          @profile = nil
        else
          ::NewRelic::Agent.logger.debug("Starting thread profile. profile_id=#{profile_id}, duration=#{duration}")
          @profile = ThreadProfile.new(profile_id, duration, interval, profile_agent_code)
          @profile.run
        end
      end

      def stop(report_data)
        @profile.stop unless @profile.nil?
        @profile = nil if !report_data
      end

      def harvest
        profile = @profile
        @profile = nil
        profile
      end

      def respond_to_commands(commands, &notify_results)
        return if commands.empty? || commands.first.size < 2 

        # Doesn't deal with multiple commands in the return set  as 
        # we currently only have start/stop of thread profiling
        command_id = commands.first[0]
        command = commands.first[1]

        name = command["name"]
        arguments = command["arguments"]

        if (ThreadProfiler.is_supported?)
          case name
            when "start_profiler"
              start_unless_running_and_notify(command_id, arguments, &notify_results)

            when "stop_profiler"
              stop_and_notify(command_id, arguments, &notify_results)
          end
        else
          msg = <<-EOF
Thread profiling is only supported on 1.9.2 and greater versions of Ruby.
We detected running agents capable of profiling, but the profile started with
an agent running Ruby #{RUBY_VERSION}.

Profiling again might select an appropriate agent, but we recommend running a
consistent version of Ruby across your application for better results.
EOF
          ::NewRelic::Agent.logger.debug(msg)
          notify_results.call(command_id, msg) if !notify_results.nil?
        end
      end

      def running?
        !@profile.nil?
      end

      def finished?
        @profile && @profile.finished?
      end

      private

      def start_unless_running_and_notify(command_id, arguments)
        profile_id = arguments.fetch("profile_id", -1)
        duration =   arguments.fetch("duration", 120)
        interval =   arguments.fetch("sample_period", 0.1)
        profile_agent_code = arguments.fetch("profile_agent_code", true)

        if running?
          msg = "Profile already in progress. Ignoring agent command to start another."
          ::NewRelic::Agent.logger.debug(msg)
          yield(command_id, msg) if block_given?
        else
          start(profile_id, duration, interval, profile_agent_code)
          yield(command_id) if block_given?
        end
      end

      def stop_and_notify(command_id, arguments)
        report_data = arguments.fetch("report_data", true)
        stop(report_data)
        yield(command_id) if block_given?
      end

    end

    class ThreadProfile

      attr_reader :profile_id, 
        :traces, 
        :profile_agent_code, :interval, 
        :poll_count, :sample_count, 
        :start_time, :stop_time

      def initialize(profile_id, duration, interval, profile_agent_code)
        @profile_id = profile_id
        @profile_agent_code = profile_agent_code

        @worker_loop = NewRelic::Agent::WorkerLoop.new(:duration => duration)
        @interval = interval
        @finished = false

        @traces = {
          :agent => [],
          :background => [],
          :other => [],
          :request => []
        }
        @flattened_nodes = []

        @poll_count = 0
        @sample_count = 0
        @failure_count = 0
      end

      def run
        AgentThread.new('Thread Profiler') do
          @start_time = now_in_millis

          @worker_loop.run(@interval) do
            NewRelic::Agent.instance.stats_engine.
              record_supportability_metrics_timed("ThreadProfiler/PollingTime") do

              @poll_count += 1
              AgentThread.list.each do |t|
                bucket = AgentThread.bucket_thread(t, @profile_agent_code)
                if bucket != :ignore
                  backtrace = AgentThread.scrub_backtrace(t, @profile_agent_code)
                  if backtrace.nil?
                    @failure_count += 1
                  else
                    @sample_count += 1
                    aggregate(backtrace, @traces[bucket])
                  end
                end
              end
            end
          end

          mark_done
          ::NewRelic::Agent.logger.debug("Finished thread profile. #{@sample_count} backtraces, #{@failure_count} failures. Will send with next harvest.")
          NewRelic::Agent.instance.stats_engine.
            record_supportability_metrics_count(@failure_count, "ThreadProfiler/BacktraceFailures")
        end
      end

      def stop
        @worker_loop.stop
        mark_done
        ::NewRelic::Agent.logger.debug("Stopping thread profile.")
      end

      def aggregate(trace, trees=@traces[:request], parent=nil)
        return nil if trace.nil? || trace.empty?
        node = Node.new(trace.last)
        existing = trees.find {|n| n == node}

        if existing.nil?
          existing = node
          @flattened_nodes << node
        end

        if parent
          parent.add_child(node)
        else
          trees << node unless trees.include? node
        end

        existing.runnable_count += 1
        aggregate(trace[0..-2], existing.children, existing)

        existing
      end

      def prune!(count_to_keep)
        @flattened_nodes.sort!(&:order_for_pruning)

        NewRelic::Agent.instance.stats_engine.
          record_supportability_metrics_count(@flattened_nodes.size, "ThreadProfiler/NodeCount")

        mark_for_pruning(@flattened_nodes, count_to_keep)

        traces.each { |_, nodes| Node.prune!(nodes) }
      end

      THREAD_PROFILER_NODES = 20_000

      def to_collector_array(encoder)
        prune!(THREAD_PROFILER_NODES)

        traces = {
          "OTHER" => @traces[:other].map{|t| t.to_array },
          "REQUEST" => @traces[:request].map{|t| t.to_array },
          "AGENT" => @traces[:agent].map{|t| t.to_array },
          "BACKGROUND" => @traces[:background].map{|t| t.to_array }
        }

        [[@profile_id,
          @start_time.to_f, @stop_time.to_f,
          @poll_count,
          encoder.encode(traces),
          @sample_count, 0]]
      end

      def now_in_millis
        Time.now.to_f * 1_000
      end

      def finished?
        @finished
      end

      def mark_done
        @finished = true
        @stop_time = now_in_millis
      end

      def mark_for_pruning(nodes, count_to_keep)
        to_prune = nodes[count_to_keep..-1] || []
        to_prune.each { |n| n.to_prune = true }
      end

      def self.flattened_nodes(nodes)
        nodes.map { |n| [n, flattened_nodes(n.children)] }.flatten
      end

      def self.parse_backtrace(trace)
        trace.map do |line|
          line =~ /(.*)\:(\d+)\:in `(.*)'/
          { :method => $3, :line_no => $2.to_i, :file => $1 }
        end
      end

      class Node
        attr_reader :file, :method, :line_no, :children
        attr_accessor :runnable_count, :to_prune, :depth

        def initialize(line, parent=nil)
          line =~ /(.*)\:(\d+)\:in `(.*)'/
          @file = $1
          @method = $3
          @line_no = $2.to_i
          @children = []
          @runnable_count = 0
          @to_prune = false
          @depth = 0

          parent.add_child(self) if parent
        end

        def ==(other)
          @file == other.file &&
            @method == other.method &&
            @line_no == other.line_no
        end

        def total_count
          @runnable_count
        end

        # Descending order on count, ascending on depth of nodes
        def order_for_pruning(y)
          [-runnable_count, depth] <=> [-y.runnable_count, y.depth]
        end

        def to_array
          [[@file, @method, @line_no],
            @runnable_count, 0,
            @children.map {|c| c.to_array}]
        end

        def add_child(child)
          child.depth = @depth + 1
          @children << child unless @children.include? child
        end

        def prune!
          Node.prune!(@children)
        end

        def self.prune!(kids)
          kids.delete_if { |child| child.to_prune }
          kids.each { |child| child.prune! }
        end
      end

    end
  end
end
