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

        response = nil
        ::NewRelic::Agent::CrossAppTracing.tl_trace_http_request(wrapped_request) do
          response = perform_without_newrelic_trace(request, options)
          ::NewRelic::Agent::HTTPClients::HTTPResponse.new(response)
        end

        response
      end

      alias perform_without_newrelic_trace perform
      alias perform perform_with_newrelic_trace
    end
  end
end
