# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module AttributeProcessing
      module_function

      EMPTY_HASH_STRING_LITERAL = '{}'.freeze
      EMPTY_ARRAY_STRING_LITERAL = '[]'.freeze
      PRE_FILTER_KEYS = %i[include exclude].freeze
      DISCARDED = :nr_discarded

      def flatten_and_coerce(object, prefix = nil, result = {}, &blk)
        if object.is_a?(Hash)
          flatten_and_coerce_hash(object, prefix, result, &blk)
        elsif object.is_a?(Array)
          flatten_and_coerce_array(object, prefix, result, &blk)
        elsif prefix
          val = Coerce.scalar(object)
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

      def formulate_regexp_union(option)
        return if NewRelic::Agent.config[option].empty?

        Regexp.union(NewRelic::Agent.config[option].map { |p| string_to_regexp(p) }.uniq.compact).freeze
      rescue StandardError => e
        NewRelic::Agent.logger.warn("Failed to formulate a Regexp union from the '#{option}' configuration option " +
                                    "- #{e.class}: #{e.message}")
      end

      def string_to_regexp(str)
        Regexp.new(str)
      rescue StandardError => e
        NewRelic::Agent.logger.warn("Failed to initialize Regexp from string '#{str}' - #{e.class}: #{e.message}")
      end

      # attribute filtering suppresses data that has already been flattened
      # and coerced (serialized as text) via #flatten_and_coerce, and is
      # restricted to basic text matching with a single optional wildcard.
      # pre filtering operates on raw Ruby objects beforehand and uses full
      # Ruby regex syntax
      def pre_filter(values = [], options = {})
        return values unless !options.empty? && PRE_FILTER_KEYS.any? { |k| options.key?(k) }

        # if there's a prefix in play for (non-pre) attribute filtration and
        # attribute filtration won't allow that prefix, then don't even bother
        # with pre filtration that could only result in values that would be
        # blocked
        if options.key?(:attribute_namespace) &&
            !NewRelic::Agent.instance.attribute_filter.might_allow_prefix?(options[:attribute_namespace])
          return values
        end

        values.each_with_object([]) do |element, filtered|
          object = pre_filter_object(element, options)
          filtered << object unless discarded?(object)
        end
      end

      def pre_filter_object(object, options)
        if object.is_a?(Hash)
          pre_filter_hash(object, options)
        elsif object.is_a?(Array)
          pre_filter_array(object, options)
        else
          pre_filter_scalar(object, options)
        end
      end

      def pre_filter_hash(hash, options)
        filtered_hash = hash.each_with_object({}) do |(key, value), filtered|
          filtered_key = pre_filter_object(key, options)
          next if discarded?(filtered_key)

          # If the key is permitted, skip include filtration for the value
          # but still apply exclude filtration
          if options.key?(:exclude)
            exclude_only = options.dup
            exclude_only.delete(:include)
            filtered_value = pre_filter_object(value, exclude_only)
            next if discarded?(filtered_value)
          else
            filtered_value = value
          end

          filtered[filtered_key] = filtered_value
        end

        filtered_hash.empty? && !hash.empty? ? DISCARDED : filtered_hash
      end

      def pre_filter_array(array, options)
        filtered_array = array.each_with_object([]) do |element, filtered|
          filtered_element = pre_filter_object(element, options)
          next if discarded?(filtered_element)

          filtered.push(filtered_element)
        end

        filtered_array.empty? && !array.empty? ? DISCARDED : filtered_array
      end

      def pre_filter_scalar(scalar, options)
        return DISCARDED if options.key?(:include) && !scalar.to_s.match?(options[:include])
        return DISCARDED if options.key?(:exclude) && scalar.to_s.match?(options[:exclude])

        scalar
      end

      # `nil`, empty enumerable objects, and `false` are all valid in their
      # own right as application data, so pre-filtering uses a special value
      # to indicate that filtered out data has been discarded
      def discarded?(object)
        object == DISCARDED
      end
    end
  end
end
