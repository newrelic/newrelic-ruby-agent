module NewRelic
  module Agent
    class PipeService
      attr_reader :channel_id, :buffer, :stats_engine
      attr_accessor :request_timeout, :agent_id, :collector
      
      def initialize(channel_id)
        @channel_id = channel_id
        @collector = NewRelic::Control::Server.new(:name => 'parent',
                                                   :port => 0)
        @stats_engine = NewRelic::Agent::StatsEngine.new
        reset_buffer
      end
      
      def connect(config)
        nil
      end
      
      def metric_data(last_harvest_time, now, unsent_timeslice_data)
        @stats_engine.merge_data(hash_from_metric_data(unsent_timeslice_data))
      end

      def transaction_sample_data(transactions)
        @buffer[:transaction_traces] += transactions
      end

      def error_data(errors)
        @buffer[:error_traces] += errors
      end

      def sql_trace_data(sql)
        @buffer[:sql_traces] += sql
      end
      
      def shutdown(time)
        @buffer[:stats] = @stats_engine.harvest_timeslice_data({}, {})
        payload = Marshal.dump(@buffer)
        NewRelic::Agent::PipeChannelManager.channels[@channel_id].write(payload)
        NewRelic::Agent::PipeChannelManager.channels[@channel_id].close
        reset_buffer
      end
      
      private

      def reset_buffer
        @buffer = {
          :stats => {},
          :transaction_traces => [],
          :error_traces => [],
          :sql_traces => []
        }
      end

      def hash_from_metric_data(metric_data)
        metric_hash = {}
        metric_data.each do |metric_entry|
          metric_hash[metric_entry.metric_spec] = metric_entry
        end
        metric_hash
      end
    end
  end
end
