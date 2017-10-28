# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/http_clients/abstract_request'

module NewRelic
  module Agent
    module HTTPClients
      class HTTPClientResponse
        attr_reader :response

        def initialize(response)
          @response = response
        end

        def [](key)
          response.headers.each do |k,v|
            if key.downcase == k.downcase
              return v
            end
          end
          nil
        end

        def to_hash
          response.headers
        end
      end

      class HTTPClientRequest < AbstractRequest
        attr_reader :request, :uri

        HTTP_CLIENT = "HTTPClient".freeze
        LHOST = 'host'.freeze
        UHOST = 'Host'.freeze
        COLON = ':'.freeze

        def initialize(request)
          @request = request
          @uri = request.header.request_uri
        end

        def type
          HTTP_CLIENT
        end

        def method
          request.header.request_method
        end

        def host_from_header
          if hostname = (self[LHOST] || self[UHOST])
            hostname.split(COLON).first
          end
        end

        def host
          host_from_header || uri.host.to_s
        end

        def [](key)
          request.headers[key]
        end

        def []=(key, value)
          request.http_header[key] = value
        end
      end
    end
  end
end
