# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Parallel
    module Instrumentation
      # This runs inside of the new process that was forked by Parallel
      def worker_with_tracing(channel_id, &block)
        NewRelic::Agent.after_fork(
          :report_to_channel => channel_id,
          :report_instance_busy => false
        )

        setup_for_txn_metric_merge_at_exit

        yield
      end

      def setup_for_txn_metric_merge_at_exit
        # Clear out any existing transaction metrics to prevent duplicates
        # when merging metrics back in at the end of the forked process
        if (txn = NewRelic::Agent::Tracer.current_transaction)
          txn.instance_variable_set(:@metrics, NewRelic::Agent::TransactionMetrics.new)
        end

        # Install at_exit hook only once per process
        unless @parallel_at_exit_installed
          @parallel_at_exit_installed = true
          at_exit do
            # Merge all newly recorded metrics back into the parent process
            # It's a little weird, but needed because the transaction does not
            # finish in the child processes, so without this the metrics would be lost.
            if (txn = NewRelic::Agent::Tracer.current_transaction)
              NewRelic::Agent.agent.stats_engine.merge_transaction_metrics!(
                txn.metrics,
                txn.best_name
              )
            end

            # force data to be sent back to the parent process
            NewRelic::Agent.agent&.stop_event_loop
            NewRelic::Agent.agent&.flush_pipe_data
          end
        end
      end
    end
  end
end
