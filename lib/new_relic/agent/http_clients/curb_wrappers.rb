# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'abstract'

module NewRelic
  module Agent
    module HTTPClients

      class CurbRequest
        CURB = 'Curb'
        LHOST = 'host'
        UHOST = 'Host'

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

      class CurbResponse < AbstractResponse

        def initialize(curlobj)
          @headers = {}
          @curlobj = curlobj
        end

        def [](key)
          @headers[ key.downcase ]
        end

        def append_header_data( data )
          key, value = data.split( /:\s*/, 2 )
          @headers[ key.downcase ] = value
          @curlobj._nr_header_str ||= String.new
          @curlobj._nr_header_str << data
        end

        def status_code
          @curlobj.response_code
        end
      end

    end

  end
end
