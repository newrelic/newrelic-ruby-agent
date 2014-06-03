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
          unless headers.nil?
            result = headers[key]

            # Typhoeus 0.5.3 has a bug where asking the headers hash for a
            # non-existent header will return the hash itself, not what we want.
            result == headers ? nil : result
          end
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
          @response.headers
        end
      end

      class TyphoeusHTTPRequest
        def initialize(request)
          @request = request
          @uri = case request.url
            when ::URI then request.url
            else NewRelic::Agent::HTTPClients::URIUtil.parse_url(request.url)
            end
        end

        def type
          "Typhoeus"
        end

        def host
          self['host'] || self['Host'] || @uri.host
        end

        def method
          (@request.options[:method] || 'GET').to_s.upcase
        end

        def [](key)
          return nil unless @request.options && @request.options[:headers]
          @request.options[:headers][key]
        end

        def []=(key, value)
          @request.options[:headers] ||= {}
          @request.options[:headers][key] = value
        end

        def uri
          @uri
        end
      end
    end
  end
end
