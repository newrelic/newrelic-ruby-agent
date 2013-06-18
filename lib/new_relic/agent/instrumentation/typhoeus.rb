# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :typhoeus

  depends_on do
    defined?(Typhoeus)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Typhoeus instrumentation (without Hydra mode support)'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/typhoeus_wrappers'
  end

  executes do
    Typhoeus.before do |request|
      if NewRelic::Agent.is_execution_traced? && request.hydra.nil?
        wrapped_request = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(request)
        t0, segment = ::NewRelic::Agent::CrossAppTracing.start_trace(wrapped_request)
        request.on_complete do
          wrapped_response = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(request.response)
          ::NewRelic::Agent::CrossAppTracing.finish_trace(t0, segment, wrapped_request, wrapped_response)
        end
      end

      # Ensure that we always return a truthy value from the before block,
      # otherwise Typhoeus will bail out of the instrumentation.
      true
    end
  end
end
