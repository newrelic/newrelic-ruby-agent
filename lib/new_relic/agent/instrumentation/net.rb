# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :net_http

  depends_on do
    defined?(Net) && defined?(Net::HTTP)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Net instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/net_http_wrappers'
  end

  executes do
    class Net::HTTP
      def request_with_newrelic_trace(request, *args, &block)
        wrapped_request = NewRelic::Agent::HTTPClients::NetHTTPRequest.new(self, request)

        segment = NewRelic::Agent::Transaction.start_external_request_segment(
          library: wrapped_request.type,
          uri: wrapped_request.uri,
          procedure: wrapped_request.method
        )

        begin
          response = nil
          segment.add_request_headers wrapped_request

          # RUBY-1244 Disable further tracing in request to avoid double
          # counting if connection wasn't started (which calls request again).
          NewRelic::Agent.disable_all_tracing do
            response = request_without_newrelic_trace( request, *args, &block )
          end

          segment.read_response_headers response
          response
        ensure
          segment.finish
        end
      end

      alias request_without_newrelic_trace request
      alias request request_with_newrelic_trace
    end
  end
end
