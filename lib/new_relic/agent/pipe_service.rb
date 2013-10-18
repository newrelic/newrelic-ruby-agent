# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class PipeService
      attr_reader :channel_id, :buffer, :pipe
      attr_accessor :request_timeout, :agent_id, :collector

      def initialize(channel_id)
        @channel_id = channel_id
        @collector = NewRelic::Control::Server.new(:name => 'parent',
                                                   :port => 0)
        @pipe = NewRelic::Agent::PipeChannelManager.channels[@channel_id]
        if @pipe && @pipe.parent_pid != $$
          @pipe.after_fork_in_child
        else
          NewRelic::Agent.logger.error("No communication channel to parent process, please see https://newrelic.com/docs/ruby/resque-instrumentation for more information.")
        end
      end

      def connect(config)
        nil
      end

      def get_agent_commands
        []
      end

      def analytic_event_data(data)
        nil
      end

      def metric_data(unsent_timeslice_data)
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
        @pipe.close if @pipe
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
        @pipe.write(data) if @pipe
      end
    end
  end
end
