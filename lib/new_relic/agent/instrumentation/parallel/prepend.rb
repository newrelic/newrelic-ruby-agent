# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Parallel
    module Prepend
      include NewRelic::Agent::Instrumentation::Parallel::Instrumentation

      def worker(job_factory, options, &block)
        return super unless NewRelic::Agent.agent

        # Generate a unique channel ID for this worker
        channel_id = object_id

        # Register the pipe channel before forking
        NewRelic::Agent.register_report_channel(channel_id)

        super(job_factory, options) do |*args|
          worker_with_tracing(channel_id) { block.call(*args) }
        end
      end
    end
  end
end
