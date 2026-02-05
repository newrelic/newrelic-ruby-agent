# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Segments
        module Datastore
          def parse_operation(name, attributes)
            return attributes['db.operation'] if attributes['db.operation']

            name_downcased = name.downcase
            return name_downcased if NewRelic::Agent::Database::KNOWN_OPERATIONS.include?(name_downcased)

            NewRelic::Agent::Database.parse_operation_from_query(attributes['db.statement']) if attributes['db.statement']
          end
        end
      end
    end
  end
end
