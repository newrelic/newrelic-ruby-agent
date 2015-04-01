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
          if needs_length_limit?(value)
            value = value[0, VALUE_LIMIT]
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

        def needs_length_limit?(value)
          if value.respond_to?(:length)
            value.length > VALUE_LIMIT
          else
            false
          end
        end
      end
    end
  end
end
