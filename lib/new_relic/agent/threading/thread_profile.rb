# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/worker_loop'
require 'new_relic/agent/threading/backtrace_node'

# Intent is for this to be a data structure for representing a thread profile
# TODO: Get rid of the running/sampling in this class, externalize it elsewhere

module NewRelic
  module Agent
    module Threading

      class ThreadProfile

        attr_reader :profile_id,
          :traces,
          :profile_agent_code,
          :interval, :duration,
          :poll_count, :sample_count,
          :start_time, :stop_time

        def initialize(agent_command)
          arguments = agent_command.arguments
          @profile_id = arguments.fetch('profile_id', -1)
          @profile_agent_code = arguments.fetch('profile_agent_code', true)

          @duration = arguments.fetch('duration', 120)
          @worker_loop = NewRelic::Agent::WorkerLoop.new(:duration => duration)
          @interval = arguments.fetch('sample_period', 0.1)
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
          NewRelic::Agent.logger.debug("Starting thread profile. profile_id=#{profile_id}, duration=#{duration}")

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
            NewRelic::Agent.logger.debug("Finished thread profile. #{@sample_count} backtraces, #{@failure_count} failures. Will send with next harvest.")
            NewRelic::Agent.instance.stats_engine.
              record_supportability_metric_count("ThreadProfiler/BacktraceFailures", @failure_count)
          end
        end

        def stop
          @worker_loop.stop
          mark_done
          NewRelic::Agent.logger.debug("Stopping thread profile.")
        end

        def aggregate(trace, trees=@traces[:request], parent=nil)
          return nil if trace.nil? || trace.empty?
          node = Threading::BacktraceNode.new(trace.last)
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

          traces.each { |_, nodes| Threading::BacktraceNode.prune!(nodes) }
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

      end
    end
  end
end
