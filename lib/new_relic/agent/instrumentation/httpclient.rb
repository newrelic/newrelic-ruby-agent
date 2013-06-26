# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :httpclient

  HTTPCLIENT_MIN_VERSION = '2.3.3'

  depends_on do
    defined?(HTTPClient) && defined?(HTTPClient::VERSION)
  end

  depends_on do
    HTTPClient::VERSION >= HTTPCLIENT_MIN_VERSION
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing HTTPClient instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/httpclient_wrappers'
  end

  executes do
    class HTTPClient
      def do_get_block_with_newrelic(req, proxy, conn, &block)
        wrapped_request = NewRelic::Agent::HTTPClients::HTTPClientHTTPRequest.new(req)

        response = nil
        ::NewRelic::Agent::CrossAppTracing.trace_http_request(wrapped_request) do
          do_get_block_without_newrelic(req, proxy, conn, &block)
          response = conn.pop
          conn.push response
          ::NewRelic::Agent::HTTPClients::HTTPClientHTTPResponse.new(response)
        end
        response
      end

      alias do_get_block_without_newrelic do_get_block
      alias do_get_block do_get_block_with_newrelic
    end
  end
end
