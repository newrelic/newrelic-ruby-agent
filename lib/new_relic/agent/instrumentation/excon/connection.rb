# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module ::Excon
  class Connection
    def newrelic_connection_params
      (@connection || @data)
    end

    def newrelic_resolved_request_params(request_params)
      resolved = newrelic_connection_params.merge(request_params)
      resolved[:headers] = resolved[:headers].merge(request_params[:headers] || {})
      resolved
    end

    def request_with_newrelic_trace(params, &block)
      orig_response = nil
      resolved_params = newrelic_resolved_request_params(params)
      wrapped_request = ::NewRelic::Agent::HTTPClients::ExconHTTPRequest.new(resolved_params)
      ::NewRelic::Agent::CrossAppTracing.tl_trace_http_request(wrapped_request) do
        orig_response = request_without_newrelic_trace(resolved_params, &block)
        ::NewRelic::Agent::HTTPClients::ExconHTTPResponse.new(orig_response)
      end
      orig_response
    end

    def self.install_newrelic_instrumentation
      alias request_without_newrelic_trace request
      alias request request_with_newrelic_trace
    end
  end
end
