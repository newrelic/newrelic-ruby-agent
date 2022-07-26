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
          # BEGIN RpcServer
          ::GRPC::RpcServer.class_eval do
            include NewRelic::Agent::Instrumentation::GRPC::Server

            def add_http2_port_with_newrelic_trace(*args)
              add_http2_port_with_tracing(*args) { add_http2_port_without_newrelic_trace(*args) }
            end

            alias add_http2_port_without_newrelic_trace add_http2_port
            alias add_http2_port add_http2_port_with_newrelic_trace

            def run_with_newrelic_trace(*args)
              run_with_tracing(*args) { run_without_newrelic_trace(*args) }
            end

            alias run_without_newrelic_trace run
            alias run run_with_newrelic_trace
            # END RpcServer
          end

          # BEGIN RpcDesc
          ::GRPC::RpcDesc.class_eval do
            include NewRelic::Agent::Instrumentation::GRPC::Server

            def handle_request_response_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_request_response_without_newrelic_trace(*args) }
            end

            alias handle_request_response_without_newrelic_trace handle_request_response
            alias handle_request_response handle_request_response_with_newrelic_trace

            def handle_client_streamer_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_client_streamer_without_newrelic_trace(*args) }
            end

            alias handle_client_streamer_without_newrelic_trace handle_client_streamer
            alias handle_client_streamer handle_client_streamer_with_newrelic_trace

            def handle_server_streamer_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_server_streamer_without_newrelic_trace(*args) }
            end

            alias handle_server_streamer_without_newrelic_trace handle_server_streamer
            alias handle_server_streamer handle_server_streamer_with_newrelic_trace

            def handle_bidi_streamer_with_newrelic_trace(*args)
              handle_with_tracing(*args) { handle_bidi_streamer_without_newrelic_trace(*args) }
            end

            alias handle_bidi_streamer_without_newrelic_trace handle_bidi_streamer
            alias handle_bidi_streamer handle_bidi_streamer_with_newrelic_trace
            # END RpcDesc
          end
        end
      end
    end
  end
end
