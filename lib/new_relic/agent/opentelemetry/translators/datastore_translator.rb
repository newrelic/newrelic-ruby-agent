# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'base_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class DatastoreTranslator < BaseTranslator
        class << self
          def mappings_hash
            AttributeMappings::DATASTORE_MAPPINGS
          end

          def add_specialized_attributes(result: {}, name: nil, attributes: nil, instrumentation_scope: nil)
            operation = parse_operation(name, attributes)
            result[:for_segment_api][:operation] = operation if operation

            result
          end

          def parse_operation(name, attributes)
            operation = attributes['db.operation.name'] || attributes['db.operation']
            return operation if operation

            name_downcased = name&.downcase
            return name_downcased if NewRelic::Agent::Database::KNOWN_OPERATIONS.include?(name_downcased)

            sql = attributes['db.query.text'] || attributes['db.statement']
            NewRelic::Agent::Database.parse_operation_from_query(sql) if sql
          end
        end
      end
    end
  end
end
