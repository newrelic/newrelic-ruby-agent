# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class HttpClientOptions
  # Eventmachine::HttpClientOptions(HttpRequest) doesn't allow to add any custom
  # headers after initiating request. We add `add_header` method to
  # HttpClientOptions, so newrelic_rpm can add any custom headers
  # (eg. cross application tracing headers) to request
  def add_header(key, value)
    headers[key] = value
  end
end

module NewRelic
  module Agent
    module HTTPClients
      class EMHTTPResponse
        def initialize(response)
          @response = response
        end

        def [](key)
          @response[key] unless @response.nil?
        end

        def to_hash
          @response.dup
        end
      end

      class EMHTTPRequest
        def initialize(request)
          @request = request
          @uri = request.uri
        end

        def type
          "EMHTTPRequest"
        end

        def host
          @uri.host
        end

        def method
          (@request.method || "GET").to_s.upcase
        end

        def [](key)
          @request.headers[key]
        end

        def []=(key, value)
          @request.add_header(key, value)
        end

        def uri
          @uri
        end
      end
    end
  end
end
