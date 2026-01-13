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

        # Install at_exit hook once per process to flush data when process exits
        # Unlike Resque (which forks per job), Parallel processes multiple jobs
        # per forked process, so we only flush when the process exits
        unless @parallel_at_exit_installed
          @parallel_at_exit_installed = true
          at_exit do
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
