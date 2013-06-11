# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HTTPClients

      class CurbRequest
        def initialize( curlobj )
          @verb = verb
          @curlobj = curlobj
        end

        def type
          'Curb'
        end

        def host
          self.uri.host
        end

        def method
          raise "Need the HTTP verb"
        end

        def []( key )
          @curlobj.headers[ key ]
        end

        def []=( key, value )
          @curlobj.headers[ key ] = value
        end

        def uri
          @uri ||= URI( @curlobj.url )
        end
      end


      class CurbResponse
        extend Forwardable

        def initialize( curlobj )
          @curlobj = curlobj
          @headers = {}
        end

        def [](key)
          @headers[ key.downcase ]
        end

        def to_hash
          @headers.dup
        end

        def append_header_data( data )
          key, value = data.split( /:\s*/, 2 )
          @headers[ key.downcase ] = value
        end

      end

    end

  end
end
