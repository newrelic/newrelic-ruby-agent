require 'new_relic/agent/thread'
require 'new_relic/agent/worker_loop'

module NewRelic
  module Agent

    class ThreadProfiler

      attr_reader :profile

      def start(profile_id, duration, interval, profile_agent_code)
        if !ThreadProfiler.is_supported?
          log.debug("Not starting thread profile as it isn't supported on this environment")
          @profile = nil
        else
          log.debug("Starting thread profile. profile_id=#{profile_id}, duration=#{duration}")
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

        # Broken because:
        # Doesn't deal with multiple commands in the return set (real case?)
        # Still some parameters to support
        command_id = commands.first[0]
        command = commands.first[1]

        name = command["name"]
        arguments = command["arguments"]

        case name
          when "start_profiler"
            start_unless_running_and_notify(command_id, arguments, &notify_results)

          when "stop_profiler"
            stop_and_notify(command_id, arguments, &notify_results)
        end
      end

      def self.is_supported?
        RUBY_VERSION >= "1.9.2"
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
          log.debug(msg)
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

      def log
        NewRelic::Agent.logger
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

        @worker_loop = NewRelic::Agent::WorkerLoop.new(duration)
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
        Thread.new('Thread Profiler') do
          @start_time = now_in_millis
          
          @worker_loop.run(@interval) do
            NewRelic::Agent.instance.stats_engine.
              record_supportability_metrics_timed("ThreadProfiler/PollingTime") do

              @poll_count += 1
              Thread.list.each do |t|
                @sample_count += 1

                bucket = Thread.bucket_thread(t, @profile_agent_code)
                aggregate(t.backtrace, @traces[bucket]) unless bucket == :ignore
              end
            end
          end

          @finished = true
          @stop_time = now_in_millis
          log.debug("Finished thread profile. Will send with next harvest.")
        end
      end

      def stop
        log.debug("Stopping thread profile.")
        @worker_loop.stop
        @finished = true
      end

      def aggregate(trace, trees=@traces[:request], parent=nil)
        return nil if trace.nil? || trace.empty?
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

      def to_compressed_array
        traces = {
          "OTHER" => @traces[:other].map{|t| t.to_array },
          "REQUEST" => @traces[:request].map{|t| t.to_array },
          "AGENT" => @traces[:agent].map{|t| t.to_array },
          "BACKGROUND" => @traces[:background].map{|t| t.to_array }
        }

        [[@profile_id,
          @start_time.to_f, @stop_time.to_f,
          @poll_count, 
          ThreadProfile.compress(JSON.dump(traces)),
          @sample_count, 0]]
      end

      def now_in_millis
        Time.now.to_f * 1_000
      end

      def finished?
        @finished
      end

      def self.compress(json)
        compressed = Base64.encode64(Zlib::Deflate.deflate(json, Zlib::DEFAULT_COMPRESSION))
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

      def log
        NewRelic::Agent.logger
      end
    end
  end
end
