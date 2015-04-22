# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HTTPClients
      class ExconHTTPResponse
        def initialize(response)
          @response = response
          # Since HTTP headers are case-insensitive, we normalize all of them to
          # upper case here, and then also in our [](key) implementation.
          @normalized_headers = {}
          headers = response.respond_to?(:headers) ? response.headers : response[:headers]
          (headers || {}).each do |key, val|
            @normalized_headers[key.upcase] = val
          end
        end

        def [](key)
          @normalized_headers[key.upcase]
        end

        def to_hash
          @normalized_headers.dup
        end
      end

      class ExconHTTPRequest
        def initialize(datum)
          @datum = datum

          @method = @datum[:method].to_s.upcase
          @scheme = @datum[:scheme]
          @port   = @datum[:port]
          @path   = @datum[:path]

          headers = @datum[:headers]
          if hostname = (headers['host'] || headers['Host'])
            @host = hostname.split(':').first
          else
            @host = @datum[:host]
          end
        end

        attr_reader :host, :method

        def type
          "Excon"
        end

        def [](key)
          @datum[:headers][key]
        end

        def []=(key, value)
          @datum[:headers] ||= {}
          @datum[:headers][key] = value
        end

        def uri
          URI.parse("#{@scheme}://#{@host}:#{@port}#{@path}")
        end
      end
    end
  end
end
