# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module AttributeProcessing
      module_function

      EMPTY_HASH_STRING_LITERAL = '{}'.freeze
      EMPTY_ARRAY_STRING_LITERAL = '[]'.freeze
      MAX_ATTRIBUTE_SIZE = 4095
      MAX_NAME_SIZE = 255

      def flatten_and_coerce(object, prefix = nil, result = {}, &blk)
        if object.is_a?(Hash)
          flatten_and_coerce_hash(object, prefix, result, &blk)
        elsif object.is_a?(Array)
          flatten_and_coerce_array(object, prefix, result, &blk)
        elsif prefix
          val = Coerce.scalar(object)
          # truncate val to 4095 bytes
          val = val.byteslice(0, MAX_ATTRIBUTE_SIZE) if val.is_a?(String) && val.bytesize > MAX_ATTRIBUTE_SIZE
          prefix = prefix.byteslice(0, MAX_NAME_SIZE) if prefix.is_a?(String) && prefix.bytesize > MAX_NAME_SIZE
          if blk
            yield(prefix, val)
          elsif !val.nil?
            result[prefix] = val
          end
        else
          NewRelic::Agent.logger.warn("Unexpected object: #{object.inspect} with nil prefix passed to NewRelic::Agent::AttributeProcessing.flatten_and_coerce")
        end
        result
      end

      def flatten_and_coerce_hash(hash, prefix, result, &blk)
        if hash.empty?
          if blk
            yield(prefix, EMPTY_HASH_STRING_LITERAL)
          else
            result[prefix] = EMPTY_HASH_STRING_LITERAL
          end
        else
          hash.each do |key, val|
            next_prefix = prefix ? "#{prefix}.#{key}" : key.to_s
            flatten_and_coerce(val, next_prefix, result, &blk)
          end
        end
      end

      def flatten_and_coerce_array(array, prefix, result, &blk)
        if array.empty?
          if blk
            yield(prefix, EMPTY_ARRAY_STRING_LITERAL)
          else
            result[prefix] = EMPTY_ARRAY_STRING_LITERAL
          end
        else
          array.each_with_index do |val, idx|
            next_prefix = prefix ? "#{prefix}.#{idx}" : idx.to_s
            flatten_and_coerce(val, next_prefix, result, &blk)
          end
        end
      end
    end
  end
end
