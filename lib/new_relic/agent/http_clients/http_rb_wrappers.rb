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
          _, value = response.headers.find { |k,_| key.downcase == k.downcase }
          value unless value.nil?
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

        def host
          if hostname = self['host']
            hostname.split(':').first
          else
            request.host
          end
        end

        def method
          request.verb.upcase
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
