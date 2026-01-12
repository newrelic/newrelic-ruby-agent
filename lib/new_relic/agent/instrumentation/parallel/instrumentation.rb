# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Parallel
    module Instrumentation
      # Wraps the worker block with pipe communication setup for child processes
      def worker_with_tracing(channel_id, &block)
        # In the child process after fork, set up pipe communication
        NewRelic::Agent.after_fork(
          :report_to_channel => channel_id,
          :report_instance_busy => false
        )

        begin
          # Execute the original block
          yield
        ensure
          # Flush data through pipe before child exits
          NewRelic::Agent.agent.stop_event_loop
          NewRelic::Agent.agent.flush_pipe_data
        end
      end
    end
  end
end
