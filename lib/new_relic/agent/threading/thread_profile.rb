# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'set'
require 'new_relic/agent/worker_loop'
require 'new_relic/agent/threading/backtrace_node'

# Data structure for representing a thread profile

module NewRelic
  module Agent
    module Threading

      class ThreadProfile

        attr_reader :profile_id, :traces, :sample_period,
          :duration, :poll_count, :backtrace_count, :failure_count,
          :created_at, :xray_id, :command_arguments, :profile_agent_code
        attr_accessor :finished_at

        def initialize(command_arguments={})
          @command_arguments  = command_arguments
          @profile_id         = command_arguments.fetch('profile_id', -1)
          @duration           = command_arguments.fetch('duration', 120)
          @sample_period      = command_arguments.fetch('sample_period', 0.1)
          @profile_agent_code = command_arguments.fetch('profile_agent_code', false)
          @xray_id            = command_arguments.fetch('x_ray_id', nil)
          @finished = false

          @traces = {
            :agent      => BacktraceRoot.new,
            :background => BacktraceRoot.new,
            :other      => BacktraceRoot.new,
            :request    => BacktraceRoot.new
          }

          @poll_count = 0
          @backtrace_count = 0
          @failure_count = 0
          @unique_threads = []

          @created_at = Time.now
        end

        def requested_period
          @sample_period
        end

        def increment_poll_count
          @poll_count += 1
        end

        def sample_count
          xray? ? @backtrace_count : @poll_count
        end

        def xray?
          !!@xray_id
        end

        def empty?
          @backtrace_count == 0
        end

        def unique_thread_count
          return 0 if @unique_threads.nil?
          @unique_threads.length
        end

        def aggregate(backtrace, bucket, thread)
          if backtrace.nil?
            @failure_count += 1
          else
            @backtrace_count += 1
            @traces[bucket].aggregate(backtrace)
            @unique_threads << thread unless @unique_threads.include?(thread)
          end
        end

        def convert_N_trace_nodes_to_arrays(count_to_keep) #THREAD_LOCAL_ACCESS
          all_nodes = @traces.values.map { |n| n.flattened }.flatten

          NewRelic::Agent.instance.stats_engine.
            tl_record_supportability_metric_count("ThreadProfiler/NodeCount", all_nodes.size)

          all_nodes.sort! do |a, b|
            # we primarily prefer higher runnable_count
            comparison = b.runnable_count <=> a.runnable_count
            # we secondarily prefer lower depth
            comparison = a.depth          <=> b.depth if comparison == 0
            # it is thus impossible for any child to preceed their parent
            comparison
          end

          all_nodes.each_with_index do |n, i|
            break if i >= count_to_keep
            n.mark_for_array_conversion
          end
          all_nodes.each_with_index do |n, i|
            break if i >= count_to_keep
            n.complete_array_conversion
          end
        end

        THREAD_PROFILER_NODES = 20_000

        include NewRelic::Coerce

        def generate_traces
          convert_N_trace_nodes_to_arrays(THREAD_PROFILER_NODES)

          {
            "OTHER"      => @traces[:other     ].as_array,
            "REQUEST"    => @traces[:request   ].as_array,
            "AGENT"      => @traces[:agent     ].as_array,
            "BACKGROUND" => @traces[:background].as_array
          }
        end

        def to_collector_array(encoder)
          encoded_trace_tree = encoder.encode(generate_traces, :skip_normalization => true)
          result = [
            int(self.profile_id),
            float(self.created_at),
            float(self.finished_at),
            int(self.sample_count),
            encoded_trace_tree,
            int(self.unique_thread_count),
            0 # runnable thread count, which we don't track
          ]
          result << int(@xray_id) if xray?
          result
        end

        def to_log_description
          id = if xray?
                 "@xray_id: #{xray_id}"
               else
                 "@profile_id: #{profile_id}"
               end

          "#<ThreadProfile:#{object_id} #{id} @command_arguments=#{@command_arguments.inspect}>"
        end

      end
    end
  end
end
