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
  end

  executes do
    class Net::HTTP

      # Instrument outgoing HTTP requests and fire associated events back
      # into the Agent.
      def request_with_newrelic_trace(request, *args, &block)
        NewRelic::Agent::CrossAppTracing.trace_http_request( self, request ) do
          request_without_newrelic_trace( request, *args, &block )
        end
      end

      alias request_without_newrelic_trace request
      alias request request_with_newrelic_trace
    end
  end
end
