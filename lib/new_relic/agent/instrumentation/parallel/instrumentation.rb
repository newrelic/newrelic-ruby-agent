# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Parallel
    module Instrumentation
      # Wraps the worker block with pipe communication setup for child processes
      def worker_with_tracing(channel_id, &block)
        # In the child process after fork, set up pipe communication
        # This is safe to call multiple times - it will only do the work once
        NewRelic::Agent.after_fork(
          :report_to_channel => channel_id,
          :report_instance_busy => false
        )

        # If a transaction exists (inherited from parent), replace its metrics container
        # with a fresh one. This preserves the transaction context (name, scope, etc.)
        # but discards any metrics recorded by the parent before the fork.
        # Only child's new metrics will be in the fresh container.
        if (txn = NewRelic::Agent::Tracer.current_transaction)
          txn.instance_variable_set(:@metrics, NewRelic::Agent::TransactionMetrics.new)
        end

        # Install at_exit hook once per process to flush data when process exits
        # Unlike Resque (which forks per job), Parallel processes multiple jobs
        # per forked process, so we only flush when the process exits
        unless @parallel_at_exit_installed
          @parallel_at_exit_installed = true
          at_exit do
            if (txn = NewRelic::Agent::Tracer.current_transaction)
              NewRelic::Agent.agent.stats_engine.merge_transaction_metrics!(
                txn.metrics,
                txn.best_name
              )
            end

            NewRelic::Agent.agent&.stop_event_loop
            NewRelic::Agent.agent&.flush_pipe_data
          end
        end

        # Execute the original block
        yield
      end
    end
  end
end
