# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'attribute_mappings'

module NewRelic
  module Agent
    module OpenTelemetry
      class BaseTranslator
        include AttributeMappings

        class << self
          # This method should be redefined in child classes.
          # The body of the method should be the mappings constant defined in the
          #  AttributesMappings module for the attribute type being translated
          def mappings_hash
            # no-op
            {}
          end

          # The translate method iterates through the mappings_hash to assign the
          # provided attributes into the correct categories
          #
          # @param attributes [optional Hash] The attributes provided to the Tracer or Span API
          # @param name [optional String] The span name provided to the Tracer#start_span API
          # @param instrumentation_scope [optional Strin] The tracer name provided to the Tracer#start_span API
          #
          # @return [Hash] A hash with attributes divided into various categories for assignment on a New Relic
          # transaction or segment.
          def translate(attributes: {}, name: nil, instrumentation_scope: nil)
            working_attrs = attributes.dup # shallow copy
            result = {intrinsic: {}, agent: {}, custom: {}, for_segment_api: {}, instance_variable: {}, translator: self}

            mappings_hash.each do |nr_key, mapping|
              value = extract_first_present(working_attrs, mapping[:otel_keys])
              next unless value

              case mapping[:category]
              when :intrinsic
                result[:intrinsic][nr_key] = value
              when :agent
                result[:agent][nr_key] = {value: value, destinations: mapping[:destinations]}
              when :instance_variable
                result[:instance_variable][nr_key] = value
              end

              if mapping[:segment_field]
                result[:for_segment_api][mapping[:segment_field]] = value
              end
            end

            # Call any methods unique to the category being translated to create
            # specialized attributes.
            result.merge(extra_operations(result: result, name: name, attributes: attributes, instrumentation_scope: instrumentation_scope))

            # Assign any remaining attributes as custom attributes
            result[:custom] = working_attrs

            result
          end

          # Method defined by child classes that calls any extra, unique operations
          # to craft attributes. Ex: parse_operation in DatastoreTranslator.
          #
          # @param [optional, Hash] result The result hash built by the translate method
          # @param [optional, String] name String The name provided to the translate method
          # @param [optional, Hash] attributes The attributes provided to the translate method
          # @param [optional, String] instrumentation_scope The instrumentation scope provided to the translate method
          #
          # @return [Hash] The augmented result hash
          def extra_operations(result: {}, name: nil, attributes: {}, instrumentation_scope: nil)
            # no-op
            {}
          end

          private

          # Extract the first seen translated key defined in the mappings hash
          # and delete that key from the working attrs hash.
          # If no key is found, return nil.
          def extract_first_present(attrs, keys)
            keys.each do |key|
              return attrs.delete(key) if attrs.key?(key)
            end

            nil
          end
        end
      end
    end
  end
end
