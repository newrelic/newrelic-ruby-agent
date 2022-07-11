# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'instrumentation'

module NewRelic::Agent::Instrumentation
  module GRPC
    module Server
      module Chain
        def self.instrument!
          ::GRPC::RpcServer.class_eval do
            include NewRelic::Agent::Instrumentation::GRPC::Server

            def initialize_with_newrelic_trace(*args)
              initialize_with_tracing(*args) { initialize_without_newrelic_trace(*args) }
            end

            alias initialize_without_newrelic_trace initialize
            alias initialize initialize_with_newrelic_trace

            def handle_with_newrelic_trace(service)
              handle_with_tracing(service) { handle_without_newrelic_trace(service) }
            end

            alias handle_without_newrelic_trace handle
            alias handle handle_with_newrelic_trace

            def run_with_newrelic_trace(signals, wait_interval = 60)
              run_with_tracing(signals) { run_without_newrelic_trace(signals, wait_interval) }
            end

            alias run_without_newrelic_trace run_till_terminated_or_interrupted
            alias run_till_terminated_or_interrupted run_with_newrelic_trace
          end
        end
      end
    end
  end
end
