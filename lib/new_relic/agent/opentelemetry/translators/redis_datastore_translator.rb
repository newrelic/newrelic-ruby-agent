# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'datastore_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class RedisDatastoreTranslator < DatastoreTranslator
        class << self
          def mappings_hash
            AttributeMappings::REDIS_MAPPINGS
          end
        end
      end
    end
  end
end
