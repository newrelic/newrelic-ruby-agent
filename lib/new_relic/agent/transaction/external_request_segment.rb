# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/http_clients/uri_util'

module NewRelic
  module Agent
    class Transaction
      class ExternalRequestSegment < Segment
        attr_reader :library, :uri, :procedure

        def initialize library, uri, procedure
          @library = library
          @uri = normalize_uri uri
          @procedure = procedure
          super()
        end

        def name
          @name ||= "External/#{host}/#{library}/#{procedure}"
        end

        def host
          uri.host
        end

        private

        def normalize_uri uri
          uri.is_a?(URI) ? uri : HTTPClients::URIUtil.parse_url(uri)
        end
      end
    end
  end
end
