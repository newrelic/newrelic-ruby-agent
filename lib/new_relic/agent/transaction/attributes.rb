# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class Attributes

        KEY_LIMIT   = 255
        VALUE_LIMIT = 255

        CAN_BYTESLICE = String.instance_methods.include?(:byteslice)

        def initialize(filter)
          @filter = filter
          @attributes = {}
          @destinations = {}
        end

        def [](key)
          @attributes[key]
        end

        def add(key, value, default_destinations = NewRelic::Agent::AttributeFilter::DST_ALL)
          if exceeds_bytesize_limit?(value, VALUE_LIMIT)
            value = slice(value)
          end

          @destinations[key] = @filter.apply(key, default_destinations)
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
            if @filter.allows?(@destinations[key], destination)
              memo[key] = value
            end
            memo
          end
        end

        def exceeds_bytesize_limit?(value, limit)
          if value.respond_to?(:bytesize)
            value.bytesize > limit
          elsif value.is_a?(Symbol)
            value.to_s.bytesize > limit
          else
            false
          end
        end

        # Take one byte past our limit. Why? This lets us unconditionally chop!
        # the end. It'll either remove the one-character-too-many we have, or
        # peel off the partial, mangled character left by the byteslice.
        def slice(incoming)
          if CAN_BYTESLICE
            result = incoming.to_s.byteslice(0, VALUE_LIMIT + 1)
          else
            # < 1.9.3 doesn't have byteslice, so we take off bytes instead.
            result = incoming.to_s.bytes.take(VALUE_LIMIT + 1).pack("C*")
          end

          result.chop!
          result
        end
      end
    end
  end
end
