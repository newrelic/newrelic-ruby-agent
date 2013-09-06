# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'set'
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
          :poll_count, :sample_count

        def initialize(agent_command)
          arguments = agent_command.arguments
          @profile_id = arguments.fetch('profile_id', -1)
          @profile_agent_code = arguments.fetch('profile_agent_code', true)

          @duration = arguments.fetch('duration', 120)
          @worker_loop = NewRelic::Agent::WorkerLoop.new(:duration => duration)
          @interval = arguments.fetch('sample_period', 0.1)
          @finished = false

          @traces = {
            :agent      => BacktraceNode.new(nil),
            :background => BacktraceNode.new(nil),
            :other      => BacktraceNode.new(nil),
            :request    => BacktraceNode.new(nil)
          }

          @poll_count = 0
          @sample_count = 0
          @failure_count = 0
        end

        def collect_thread_backtrace(thread)
          bucket = Threading::AgentThread.bucket_thread(thread, @profile_agent_code)
          return if bucket == :ignore

          backtrace = Threading::AgentThread.scrub_backtrace(thread, @profile_agent_code)

          if backtrace
            @sample_count += 1
            aggregate(backtrace, bucket)
          else
            @failure_count += 1
          end
        end

        def run
          NewRelic::Agent.logger.debug("Starting thread profile. profile_id=#{profile_id}, duration=#{duration}")

          Threading::AgentThread.new('Thread Profiler') do
            @worker_loop.run(@interval) do
              NewRelic::Agent.instance.stats_engine.
                record_supportability_metric_timed("ThreadProfiler/PollingTime") do

                @poll_count += 1
                Threading::AgentThread.list.each do |t|
                  collect_thread_backtrace(t)
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

        def aggregate(backtrace, bucket=:request)
          current = @traces[bucket]

          backtrace.reverse_each do |frame|
            node = Threading::BacktraceNode.new(frame)

            existing_node = current.find(node)
            if existing_node
              node = existing_node
            else
              current.add_child_unless_present(node)
            end

            node.runnable_count += 1
            current = node
          end
        end

        def prune!(count_to_keep)
          all_nodes = @traces.values.map(&:flatten).flatten

          NewRelic::Agent.instance.stats_engine.
            record_supportability_metric_count("ThreadProfiler/NodeCount", all_nodes.size)

          all_nodes.sort!
          nodes_to_prune = Set.new(all_nodes[count_to_keep..-1] || [])
          traces.values.each { |root| root.prune!(nodes_to_prune) }
        end

        THREAD_PROFILER_NODES = 20_000

        include NewRelic::Coerce

        def start_time
          @worker_loop.start_time
        end

        def stop_time
          @worker_loop.stop_time
        end

        def to_collector_array(encoder)
          prune!(THREAD_PROFILER_NODES)

          traces = {
            "OTHER" => @traces[:other].to_array,
            "REQUEST" => @traces[:request].to_array,
            "AGENT" => @traces[:agent].to_array,
            "BACKGROUND" => @traces[:background].to_array
          }

          [[
            int(@profile_id),
            float(start_time),
            float(stop_time),
            int(@poll_count),
            string(encoder.encode(traces)),
            int(@sample_count),
            0
          ]]
        end

        def finished?
          @finished
        end

        def mark_done
          @finished = true
        end
      end
    end
  end
end
