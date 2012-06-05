module NewRelic
  module Agent
    class PipeService
      attr_reader :channel_id, :buffer
      attr_accessor :request_timeout, :agent_id, :collector
      
      def initialize(channel_id)
        @channel_id = channel_id
        @collector = NewRelic::Control::Server.new(:name => 'parent',
                                                   :port => 0)
      end
      
      def connect(config)
        nil
      end
      
      def metric_data(last_harvest_time, now, unsent_timeslice_data)
        write_to_pipe(:stats => hash_from_metric_data(unsent_timeslice_data))
        {}
      end

      def transaction_sample_data(transactions)
        write_to_pipe(:transaction_traces => transactions) if transactions
      end

      def error_data(errors)
        write_to_pipe(:error_traces => errors) if errors
      end

      def sql_trace_data(sql)
        write_to_pipe(:sql_traces => sql) if sql
      end
      
      def shutdown(time)
        write_to_pipe('EOF')
        NewRelic::Agent::PipeChannelManager.channels[@channel_id].close
      end
      
      private

      def hash_from_metric_data(metric_data)
        metric_hash = {}
        metric_data.each do |metric_entry|
          metric_hash[metric_entry.metric_spec] = metric_entry
        end
        metric_hash
      end

      def write_to_pipe(data)
        NewRelic::Agent::PipeChannelManager.channels[@channel_id].write(data)
      end
    end
  end
end
