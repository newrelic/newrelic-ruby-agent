# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'instrumentation'

module NewRelic::Agent::Instrumentation
  module GRPC
    module Server
      module Chain
        def self.instrument!
          ::GRPC::RpcServer.class_eval do
            include NewRelic::Agent::Instrumentation::GRPC::Server

            def handle_request_response_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_request_response_without_newrelic_trace }
            end

            alias handle_request_response_without_newrelic_trace handle_request_response
            alias handle_request_response handle_request_response_with_newrelic_trace

            def handle_client_streamer_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_client_streamer_without_newrelic_trace }
            end

            alias handle_client_streamer_without_newrelic_trace handle_client_streamer
            alias handle_client_streamer handle_client_streamer_with_newrelic_trace

            def handle_server_streamer_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_server_streamer_without_newrelic_trace }
            end

            alias handle_server_streamer_without_newrelic_trace handle_server_streamer
            alias handle_server_streamer handle_server_streamer_with_newrelic_trace

            def handle_bidi_streamer_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_bidi_streamer_without_newrelic_trace }
            end

            alias handle_bidi_streamer_without_newrelic_trace handle_bidi_streamer
            alias handle_bidi_streamer handle_bidi_streamer_with_newrelic_trace
          end
        end
      end
    end
  end
end
