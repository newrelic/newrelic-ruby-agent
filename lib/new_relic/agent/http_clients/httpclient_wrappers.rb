# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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

      class HTTPClientRequest
        attr_reader :request, :uri

        def initialize(request)
          @request = request
          @uri = request.header.request_uri
        end

        def type
          "HTTPClient"
        end

        def method
          request.header.request_method
        end

        def host
          if hostname = (self['host'] || self['Host'])
            hostname.split(':').first
          else
            uri.host.to_s
          end
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
