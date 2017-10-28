# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/http_clients/abstract_request'

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

      class HTTPRequest < AbstractRequest
        HTTP_RB = 'http.rb'.freeze
        HOST    = 'host'.freeze
        COLON   = ':'.freeze

        attr_reader :request, :uri

        def initialize(request)
          @request = request
          @uri = request.uri
        end

        def type
          HTTP_RB
        end

        def host_from_header
          if hostname = self[HOST]
            hostname.split(COLON).first
          end
        end

        def host
          host_from_header || request.host
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
