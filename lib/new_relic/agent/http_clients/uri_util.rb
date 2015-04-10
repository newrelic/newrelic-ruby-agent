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
    module HTTPClients
      module URIUtil

        def self.filter_uri(original)
          filtered = original.dup
          filtered.user = nil
          filtered.password = nil
          filtered.query = nil
          filtered.fragment = nil
          filtered.to_s
        end

        # There are valid URI strings that some HTTP client libraries will
        # accept that the stdlib URI module doesn't handle. If we find that
        # Addressable is around, use that to normalize out our URL's.
        def self.parse_url(url)
          if defined?(::Addressable::URI)
            address = ::Addressable::URI.parse(url)
            address.normalize!
            URI.parse(address.to_s)
          else
            URI.parse(url)
          end
        end

        QUESTION_MARK = "?".freeze

        def self.strip_query_string(fragment)
          if(fragment.include?(QUESTION_MARK))
            fragment.split(QUESTION_MARK).first
          else
            fragment
          end
        end
      end
    end
  end
end
