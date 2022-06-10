# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Client
          module Prepend
            include NewRelic::Agent::Instrumentation::GRPC::Client

            def initialize(*args)
              initialize_with_tracing(*args) { super }
            end

            def bidi_streamer(*args)
              issue_request_with_tracing(*args) { super }
            end

            def client_streamer(*args)
              issue_request_with_tracing(*args) { super }
            end

            def request_response(*args)
              issue_request_with_tracing(*args) { super }
            end

            def server_streamer(*args)
              issue_request_with_tracing(*args) { super }
            end
          end
        end
      end
    end
  end
end
