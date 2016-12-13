# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :httprb

  depends_on do
    defined?(HTTP) && defined?(HTTP::Client)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing http.rb instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/http_rb_wrappers'
  end

  executes do
    class HTTP::Client
      def perform_with_newrelic_trace(request, options)
        wrapped_request = ::NewRelic::Agent::HTTPClients::HTTPRequest.new(request)

        begin
          segment = NewRelic::Agent::Transaction.start_external_request_segment(
            wrapped_request.type, wrapped_request.uri, wrapped_request.method)

          segment.add_request_headers wrapped_request

          response = perform_without_newrelic_trace(request, options)
          segment.read_response_headers response

          response
        ensure
          segment.finish if segment
        end
      end

      alias perform_without_newrelic_trace perform
      alias perform perform_with_newrelic_trace
    end
  end
end
