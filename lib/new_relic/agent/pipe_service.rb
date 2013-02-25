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

      def get_agent_commands
        []
      end

      def metric_data(last_harvest_time, now, unsent_timeslice_data)
        write_to_pipe(:stats => unsent_timeslice_data)
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

      # Invokes the block it is passed.  This is used to implement HTTP
      # keep-alive in the NewRelicService, and is a required interface for any
      # Service class.
      def session
        yield
      end

      def reset_metric_id_cache
        # we don't cache metric IDs, so nothing to do
      end

      private

      def write_to_pipe(data)
        NewRelic::Agent::PipeChannelManager.channels[@channel_id].write(data)
      rescue => e
        NewRelic::Agent.logger.error("#{e.message}: Unable to send data to parent process, please see https://newrelic.com/docs/ruby/resque-instrumentation for more information.")
      end
    end
  end
end
