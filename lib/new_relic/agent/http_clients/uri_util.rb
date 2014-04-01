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
          uri = FilteredUri.new original
          uri.to_s
        end

        class FilteredUri
          class << self
            attr_accessor :default_filters
          end
          self.default_filters = [ :user, :password, :query, :fragment ]

          attr_accessor :original
          private :original=, :original

          attr_accessor :filter_attributes
          private :filter_attributes=, :filter_attributes

          def initialize original, filter_attributes = nil
            self.original = original
            self.filter_attributes = filter_attributes || default_filters
          end

          def to_s
            filtered = parsed_uri
            setters.each { |setter| filtered.send setter, nil }
            filtered.to_s
          end

          def default_filters
            self.class.default_filters
          end
          private :default_filters

          def setters
            filter_attributes.map { |a| "#{a}=" }
          end
          private :setters

          def parsed_uri
            return original.dup if filterable?
            URI.parse original.to_s
          end
          private :parsed_uri

          def filterable?
            setters.all? { |setter| original.respond_to? setter }
          end
          private :filterable?
        end
      end
    end
  end
end
