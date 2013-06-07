# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :net

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
      # Instrument outgoing HTTP requests
      #
      # If request is called when not the connection isn't started, request
      # will call back into itself (via a start block).
      #
      # Don't tracing until the inner call then to avoid double-counting.
      def request_with_newrelic_trace(request, *args, &block)
        if started?
          wrapped_request = NewRelic::Agent::HTTPClients::NetHTTPRequest.new(self, request)
          NewRelic::Agent::CrossAppTracing.trace_http_request( wrapped_request ) do
            request_without_newrelic_trace( request, *args, &block )
          end
        else
          request_without_newrelic_trace( request, *args, &block )
        end
      end

      alias request_without_newrelic_trace request
      alias request request_with_newrelic_trace
    end
  end
end
