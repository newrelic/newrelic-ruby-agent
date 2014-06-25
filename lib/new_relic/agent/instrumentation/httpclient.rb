# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :httpclient

  HTTPCLIENT_MIN_VERSION = '2.2.0'

  depends_on do
    defined?(HTTPClient) && defined?(HTTPClient::VERSION)
  end

  depends_on do
    minimum_supported_version = NewRelic::VersionNumber.new(HTTPCLIENT_MIN_VERSION)
    current_version = NewRelic::VersionNumber.new(HTTPClient::VERSION)

    current_version >= minimum_supported_version
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing HTTPClient instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/httpclient_wrappers'
  end

  executes do
    class HTTPClient
      def do_get_block_with_newrelic(req, proxy, conn, &block)
        wrapped_request = NewRelic::Agent::HTTPClients::HTTPClientRequest.new(req)

        response = nil
        ::NewRelic::Agent::CrossAppTracing.tl_trace_http_request(wrapped_request) do
          do_get_block_without_newrelic(req, proxy, conn, &block)
          response = conn.pop
          conn.push response
          ::NewRelic::Agent::HTTPClients::HTTPClientResponse.new(response)
        end
        response
      end

      alias do_get_block_without_newrelic do_get_block
      alias do_get_block do_get_block_with_newrelic
    end
  end
end
