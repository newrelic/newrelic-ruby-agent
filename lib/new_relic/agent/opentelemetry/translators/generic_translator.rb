# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'base_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      # The Generic translator will sends all attributes to custom attributes
      # because there are no known New Relic attributes to translate
      class GenericTranslator < BaseTranslator
        class << self
          def mappings_hash
            {}
          end
        end
      end
    end
  end
end
