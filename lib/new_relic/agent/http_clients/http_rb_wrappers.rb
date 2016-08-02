# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HTTPClients
      class HTTPResponse
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

      class HTTPRequest
        attr_reader :request, :uri

        def initialize(request)
          @request = request
          @uri = request.uri
        end

        def type
          "http.rb"
        end

        def method
          request.verb
        end

        def host
          request.socket_host
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
