# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'instrumentation'

module NewRelic::Agent::Instrumentation
  module GRPC
    module Client
      module Chain
        def self.instrument!
          ::GRPC::ClientStub.class_eval do
            include NewRelic::Agent::Instrumentation::GRPC::Client

            def initialize_with_newrelic_trace(*args)
              initialize_with_tracing(*args)
            end

            alias initialize_without_newrelic_trace initialize
            alias initialize initialize_with_newrelic_trace

            def bidi_streamer_with_newrelic_trace(*args)
              issue_request_with_tracing(*args)
            end

            alias bidi_streamer_without_newrelic_trace bidi_streamer
            alias bidi_streamer bidi_streamer_with_newrelic_tracer

            def client_streamer_with_newrelic_trace(*args)
              issue_request_with_tracing(*args)
            end

            alias client_streamer_without_newrelic_trace client_streamer
            alias client_streamer client_streamer_with_newrelic_tracer

            def request_response_with_newrelic_trace(*args)
              issue_request_with_tracing(*args)
            end

            alias request_response_without_newrelic_trace request_response
            alias request_response request_response_with_newrelic_tracer

            def server_streamer_with_newrelic_trace(*args)
              issue_request_with_tracing(*args)
            end

            alias server_streamer_without_newrelic_trace server_streamer
            alias server_streamer server_streamer_with_newrelic_tracer
          end
        end
      end
    end
  end
end
