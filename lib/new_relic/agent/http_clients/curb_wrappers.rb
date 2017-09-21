# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/http_clients/abstract_request'

module NewRelic
  module Agent
    module HTTPClients

      class CurbRequest
        CURB = 'Curb'.freeze
        LHOST = 'host'.freeze
        UHOST = 'Host'.freeze

        def initialize( curlobj )
          @curlobj = curlobj
        end

        def type
          CURB
        end

        def host_from_header
          self[LHOST] || self[UHOST]
        end

        def host
          host_from_header || self.uri.host
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
          @uri ||= NewRelic::Agent::HTTPClients::URIUtil.parse_and_normalize_url(@curlobj.url)
        end
      end


      class CurbResponse < AbstractRequest

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
