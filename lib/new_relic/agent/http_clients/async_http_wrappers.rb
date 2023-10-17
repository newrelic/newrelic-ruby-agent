# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'abstract'
require 'resolv'

module NewRelic
  module Agent
    module HTTPClients
      class AsyncHTTPResponse < AbstractResponse
        def get_status_code
          get_status_code_using(:status)
        end

        def [](key)
          @wrapped_response.headers.to_h[key.downcase]&.first
        end

        def to_hash
          @wrapped_response.headers.to_h
        end
      end

      class AsyncHTTPRequest < AbstractRequest
        def initialize(connection, method, url, headers)
          @connection = connection
          @method = method
          @url = ::NewRelic::Agent::HTTPClients::URIUtil.parse_and_normalize_url(url)
          @headers = headers
        end

        ASYNC_HTTP = 'Async::HTTP'
        LHOST = 'host'
        UHOST = 'Host'
        COLON = ':'

        def type
          ASYNC_HTTP
        end

        def host_from_header
          if hostname = (headers[LHOST] || headers[UHOST])
            hostname.split(COLON).first
          end
        end

        def host
          host_from_header || uri.host.to_s
        end

        def [](key)
          headers[key]
        end

        def []=(key, value)
          headers[key] = value
        end

        def uri
          @url
        end

        def headers
          @headers
        end

        def method
          @method
        end
      end
    end
  end
end
