module NewRelic
  module Agent
    class PipeService
      attr_reader :channel_id
      attr_reader :buffer
      
      def initialize(channel_id)
        @channel_id = channel_id
        reset_buffer
      end
      
      def connect(config)
        nil
      end
      
      def metric_data(last_harvest_time, now, unsent_timeslice_data)
        @buffer[:stats] += (unsent_timeslice_data)
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
        payload = Marshal.dump(@buffer)
        NewRelic::Agent::PipeChannelManager.channels[@channel_id].in << payload
      end
      
      private

      def reset_buffer
        @buffer = {
          :stats => [],
          :transaction_traces => [],
          :error_traces => [],
          :sql_traces => []
        }
      end
    end
  end
end
