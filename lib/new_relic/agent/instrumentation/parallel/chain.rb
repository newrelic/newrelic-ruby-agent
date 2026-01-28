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

              # Make sure the pipe channel listener is listening
              NewRelic::Agent::PipeChannelManager.listener.start unless NewRelic::Agent::PipeChannelManager.listener.started?

              # Create a unique id for the channel and register it
              channel_id = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
              NewRelic::Agent.register_report_channel(channel_id)

              worker_without_newrelic(job_factory, options) do |*args|
                worker_with_tracing(channel_id) { yield(*args) }
              end
            end
          end
        end
      end
    end
  end
end
