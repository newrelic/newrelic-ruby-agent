# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/worker_loop'

# Intent is for this to be a data structure for representing a thread profile
# TODO: Get rid of the running/sampling in this class, externalize it elsewhere

module NewRelic
  module Agent
    module Threading

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
          Threading::AgentThread.new('Thread Profiler') do
            @start_time = now_in_millis

            @worker_loop.run(@interval) do
              NewRelic::Agent.instance.stats_engine.
                record_supportability_metric_timed("ThreadProfiler/PollingTime") do

                @poll_count += 1
                Threading::AgentThread.list.each do |t|
                  bucket = Threading::AgentThread.bucket_thread(t, @profile_agent_code)
                  if bucket != :ignore
                    backtrace = Threading::AgentThread.scrub_backtrace(t, @profile_agent_code)
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
              record_supportability_metric_count("ThreadProfiler/BacktraceFailures", @failure_count)
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
            record_supportability_metric_count("ThreadProfiler/NodeCount", @flattened_nodes.size)

          mark_for_pruning(@flattened_nodes, count_to_keep)

          traces.each { |_, nodes| Node.prune!(nodes) }
        end

        THREAD_PROFILER_NODES = 20_000

        include NewRelic::Coerce

        def to_collector_array(encoder)
          prune!(THREAD_PROFILER_NODES)

          traces = {
            "OTHER" => @traces[:other].map{|t| t.to_array },
            "REQUEST" => @traces[:request].map{|t| t.to_array },
            "AGENT" => @traces[:agent].map{|t| t.to_array },
            "BACKGROUND" => @traces[:background].map{|t| t.to_array }
          }

          [[
            int(@profile_id),
            float(@start_time),
            float(@stop_time),
            int(@poll_count),
            string(encoder.encode(traces)),
            int(@sample_count),
            0
          ]]
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

          include NewRelic::Coerce

          def to_array
            [[
              string(@file),
              string(@method),
              int(@line_no)
            ],
              int(@runnable_count),
              0,
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
end
