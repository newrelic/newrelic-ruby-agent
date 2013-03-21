# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module URIUtil
      def self.filtered_uri_for(http, request)
        scheme = http.use_ssl? ? 'https' : 'http'
        parsed = URI("#{scheme}://#{http.address}:#{http.port}#{request.path}")
        parsed.query = nil
        parsed.fragment = nil
        parsed.to_s
      end
    end
  end
end