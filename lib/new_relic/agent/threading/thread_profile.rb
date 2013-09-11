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

        attr_reader :profile_id, :traces, :profile_agent_code, :interval,
          :duration, :poll_count, :sample_count, :failure_count,
          :created_at, :last_aggregated_at

        def initialize(agent_command)
          arguments = agent_command.arguments
          @profile_id = arguments.fetch('profile_id', -1)
          @profile_agent_code = arguments.fetch('profile_agent_code', true)

          @duration = arguments.fetch('duration', 120)
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

          @created_at = Time.now
          @last_aggregated_at = nil
        end

        def stop
          mark_done
          NewRelic::Agent.logger.debug("Stopping thread profile.")
        end

        def increment_poll_count
          @poll_count += 1
        end

        def aggregate(backtrace, bucket)
          if backtrace.nil?
            @failure_count += 1
          else
            @sample_count += 1
            @traces[bucket].aggregate(backtrace)
          end

          @last_aggregated_at = Time.now
        end

        def truncate_to_node_count!(count_to_keep)
          all_nodes = @traces.values.map(&:flatten).flatten

          NewRelic::Agent.instance.stats_engine.
            record_supportability_metric_count("ThreadProfiler/NodeCount", all_nodes.size)

          all_nodes.sort!
          nodes_to_prune = Set.new(all_nodes[count_to_keep..-1] || [])
          traces.values.each { |root| root.prune!(nodes_to_prune) }
        end

        THREAD_PROFILER_NODES = 20_000

        include NewRelic::Coerce

        def to_collector_array(encoder)
          truncate_to_node_count!(THREAD_PROFILER_NODES)

          traces = {
            "OTHER" => @traces[:other].to_array,
            "REQUEST" => @traces[:request].to_array,
            "AGENT" => @traces[:agent].to_array,
            "BACKGROUND" => @traces[:background].to_array
          }

          [[
            int(@profile_id),
            float(self.created_at),
            float(self.last_aggregated_at),
            int(@poll_count),
            string(encoder.encode(traces)),
            int(@sample_count),
            0
          ]]
        end

        def finished?
          @marked_done || Time.now > self.created_at + @duration
        end

        def mark_done
          @marked_done true
        end
      end
    end
  end
end
