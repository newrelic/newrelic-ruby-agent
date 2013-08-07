# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HTTPClients
      class NetHTTPRequest
        def initialize(connection, request)
          @connection = connection
          @request = request
        end

        def type
          'Net::HTTP'
        end

        def host
          if hostname = self['host']
            hostname.split(':').first
          else
            @connection.address
          end
        end

        def method
          @request.method
        end

        def [](key)
          @request[key]
        end

        def []=(key, value)
          @request[key] = value
        end

        def uri
          case @request.path
          when /^https?:\/\//
            URI(@request.path)
          else
            scheme = @connection.use_ssl? ? 'https' : 'http'
            URI("#{scheme}://#{@connection.address}:#{@connection.port}#{@request.path}")
          end
        end
      end
    end
  end
end
