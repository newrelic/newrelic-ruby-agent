# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module HTTPClients

      class CurbRequest
        def initialize( curlobj )
          @curlobj = curlobj
        end

        def type
          'Curb'
        end

        def host
          self["host"] || self["Host"] || self.uri.host
        end

        def method
          @curlobj._nr_http_verb
        end

        def []( key )
          @curlobj.headers[ key ]
        end

        def []=( key, value )
          @curlobj.headers[ key ] = value
        end

        def uri
          @uri ||= NewRelic::Agent::HTTPClients::URIUtil.parse_url(@curlobj.url)
        end
      end


      class CurbResponse

        def initialize(curlobj)
          @headers = {}
          @curlobj = curlobj
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
          @curlobj._nr_header_str ||= ''
          @curlobj._nr_header_str << data
        end

      end

    end

  end
end
