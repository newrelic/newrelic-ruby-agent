# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module includes utilities for manipulating URIs, particularly from the
# context of Net::HTTP requests. We don't always have direct access to the full
# URI from our instrumentation points in Net::HTTP, and we want to filter out
# some URI parts before saving URIs from instrumented calls - logic for that
# lives here.

module NewRelic
  module Agent
    module URIUtil
      def self.uri_from_connection_and_request(http, request)
        parsed = case request.path
        when /^https?:\/\//
          URI(request.path)
        else
          scheme = http.use_ssl? ? 'https' : 'http'
          URI("#{scheme}://#{http.address}:#{http.port}#{request.path}")
        end
      end

      def self.filtered_uri_for(http, request)
        parsed = uri_from_connection_and_request(http, request)
        filter_uri(parsed)
      end

      def self.filter_uri(uri)
        parsed = uri.dup
        parsed.user = nil
        parsed.password = nil
        parsed.query = nil
        parsed.fragment = nil
        parsed.to_s
      end
    end
  end
end
