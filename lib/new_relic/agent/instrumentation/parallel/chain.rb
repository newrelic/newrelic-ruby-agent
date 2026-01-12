# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Parallel
    module Chain
      def self.instrument!
        ::Parallel.class_eval do
          class << self
            include NewRelic::Agent::Instrumentation::Parallel::Instrumentation

            alias_method :worker_without_newrelic, :worker

            def worker(job_factory, options, &block)
              return worker_without_newrelic(job_factory, options, &block) unless NewRelic::Agent.agent

              # Generate a unique channel ID for this worker
              channel_id = object_id

              # Register the pipe channel before forking
              NewRelic::Agent.register_report_channel(channel_id)

              worker_without_newrelic(job_factory, options) do |*args|
                worker_with_tracing(channel_id) { block.call(*args) }
              end
            end
          end
        end
      end
    end
  end
end
