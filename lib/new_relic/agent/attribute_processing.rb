# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module AttributeProcessing
      module_function

      def flatten_and_coerce(object, prefix = nil, result = {})
        case object
        when Hash
          flatten_and_coerce_hash(object, prefix, result)
        when Array
          flatten_and_coerce_array(object, prefix, result)
        else
          result[prefix] = Coerce::scalar(object)
        end
        result
      end

      def flatten_and_coerce_hash(hash, prefix, result)
        if hash.empty?
            result[prefix] = "{}"
        else
          hash.each do |key, val|
            normalized_key = EncodingNormalizer.normalize_string(key.to_s)
            next_prefix = prefix ? "#{prefix}.#{normalized_key}" : normalized_key
            flatten_and_coerce(val, next_prefix, result)
          end
        end
      end

      def flatten_and_coerce_array(array, prefix, result)
        if array.empty?
          result[prefix] = "[]"
        else
          array.each_with_index do |val, idx|
            next_prefix = prefix ? "#{prefix}.#{idx}" : idx.to_s
            flatten_and_coerce(val, next_prefix, result)
          end
        end
      end
    end
  end
end