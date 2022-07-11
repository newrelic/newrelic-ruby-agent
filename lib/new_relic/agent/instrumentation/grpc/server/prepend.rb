# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Server
          module Prepend
            include NewRelic::Agent::Instrumentation::GRPC::Server

            def initialize(*args)
              initialize_with_tracing(*args) { super }
            end

            def handle(service)
              handle_with_tracing(service) { super }
            end

            def run_till_terminated_or_interrupted(signals, wait_interval = 60)
              run_with_tracing(signals, wait_interval) { super }
            end
          end
        end
      end
    end
  end
end
