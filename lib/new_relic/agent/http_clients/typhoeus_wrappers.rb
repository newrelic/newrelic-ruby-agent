# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HTTPClients
      class TyphoeusHTTPResponse
        def initialize(response)
          @response = response
        end

        def [](key)
          headers[key]
        end

        def to_hash
          hash = {}
          headers.each do |(k,v)|
            hash[k] = v
          end
          hash
        end

        private

        def headers
          headers = @response.headers_hash if @response.respond_to?(:headers_hash)
          headers = @response.headers if headers.nil?
          headers
        end
      end

      class TyphoeusHTTPRequest
        def initialize(request)
          @request = request
          @uri = URI.parse(request.url)
        end

        def type
          "Typhoeus"
        end

        def host
          @uri.host
        end

        def method
          if @request.respond_to?(:options)
            meth = @request.options[:method]
          else
            meth = @request.method
          end
          (meth || 'GET').to_s.upcase
        end

        def [](key)
          if @request.respond_to?(:headers)
            @request.headers[key]
          else
            @request[key]
          end
        end

        def []=(key, value)
          if @request.respond_to?(:headers)
            @request.headers[key] = value
          else
            @request.options[:headers] ||= {}
            @request.options[:headers][key] = value
          end
        end

        def uri
          @uri
        end
      end
    end
  end
end
