# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HTTPClients
      class HTTPClientHTTPResponse
        attr_reader :response

        def initialize(response)
          @response = response
        end

        def [](key)
          response.headers[key]
        end

        def to_hash
          headers
        end
      end

      class HTTPClientHTTPRequest
        attr_reader :request, :uri

        def initialize(request)
          @request = request
          ::NewRelic::Agent.logger.info "JMS: URI #{request.header.request_uri}"
          @uri = request.header.request_uri
        end

        def type
          "HTTPClient"
        end

        def method
          request.header.request_method
        end

        def host
          uri.host.to_s.upcase
        end

        def [](key)
          request.headers[key]
        end

        def []=(key, value)
          request.headers[key] = value
        end
      end
    end
  end
end
