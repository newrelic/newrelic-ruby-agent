# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/http_clients/abstract_request'

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

      class ExconHTTPRequest < AbstractRequest
        attr_reader :method

        EXCON = "Excon".freeze
        LHOST = 'host'.freeze
        UHOST = 'Host'.freeze
        COLON = ':'.freeze

        def initialize(datum)
          @datum = datum

          @method = @datum[:method].to_s.upcase
          @scheme = @datum[:scheme]
          @port   = @datum[:port]
          @path   = @datum[:path]
        end

        def type
          EXCON
        end

        def host_from_header
          headers = @datum[:headers]
          if hostname = (headers[LHOST] || headers[UHOST])
            hostname.split(COLON).first
          end
        end

        def host
          host_from_header || @datum[:host]
        end

        def [](key)
          @datum[:headers][key]
        end

        def []=(key, value)
          @datum[:headers] ||= {}
          @datum[:headers][key] = value
        end

        def uri
          ::NewRelic::Agent::HTTPClients::URIUtil.parse_and_normalize_url(
            "#{@scheme}://#{host}:#{@port}#{@path}"
            )
        end
      end
    end
  end
end
