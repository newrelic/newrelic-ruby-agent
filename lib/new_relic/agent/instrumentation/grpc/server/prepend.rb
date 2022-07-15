# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Server
          module Prepend
            include NewRelic::Agent::Instrumentation::GRPC::Server

            def handle_request_response(*args)
              handle_with_tracing(*args) { super }
            end

            def handle_client_streamer(*args)
              handle_with_tracing(*args) { super }
            end

            def handle_server_streamer(*args)
              handle_with_tracing(*args) { super }
            end

            def handle_bidi_streamer(*args)
              handle_with_tracing(*args) { super }
            end
          end
        end
      end
    end
  end
end
