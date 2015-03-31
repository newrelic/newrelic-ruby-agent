# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class Attributes
        def initialize(filter)
          @filter = filter
          @attributes = {}
        end

        def [](key)
          @attributes[key]
        end

        def add(key, value)
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
      end
    end
  end
end
