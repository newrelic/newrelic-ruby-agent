# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class Attributes

        KEY_LIMIT   = 255
        VALUE_LIMIT = 255

        def initialize(filter)
          @filter = filter
          @attributes = {}
        end

        def [](key)
          @attributes[key]
        end

        def add(key, value)
          if needs_length_limit?(value, VALUE_LIMIT)
            value = value.to_s[0, VALUE_LIMIT]
          end

          @attributes[key] = value
        end

        def length
          @attributes.length
        end

        def merge!(other)
          other.each do |key, value|
            self.add(key, value)
          end
        end

        def for_destination(destination)
          @attributes.inject({}) do |memo, (key, value)|
            memo[key] = value if @filter.applies?(key, destination)
            memo
          end
        end

        def needs_length_limit?(value, limit)
          if value.respond_to?(:length)
            value.length > limit
          elsif value.is_a?(Symbol)
            # Symbol lacks length on 1.8.7, so if we get here, to_s first
            value.to_s.length > limit
          else
            false
          end
        end
      end
    end
  end
end
