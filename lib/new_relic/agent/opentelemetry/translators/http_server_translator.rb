# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'base_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class HttpServerTranslator < BaseTranslator
        class << self
          def mappings_hash
            AttributeMappings::HTTP_SERVER_MAPPINGS
          end

          def extra_operations(result: {}, name: nil, attributes: nil, instrumentation_scope: nil)
            result[:for_segment_api][:name] = create_server_transaction_name(name, instrumentation_scope, attributes)

            result
          end

          def create_server_transaction_name(original_name, instrumentation_scope, attributes)
            attributes ||= NewRelic::EMPTY_HASH
            method = attributes['http.request.method'] || attributes['http.method']
            path = attributes['url.path'] || attributes['http.target']

            if method && path
              # TransactionNamer.name_for is used in ControllerInstrumentation
              # This will produce a name that looks something like:
              # "Controller/OpenTelemetry::Instrumentation::Rack/GET /path"
              # "method /path" is roughly what the semantic conventions have for
              # a server span name in the stable conventions, but the old
              # conventions prefix with HTTP; so we create the string
              # ourselves until only the stable conventions are used
              Instrumentation::ControllerInstrumentation::TransactionNamer.name_for(nil, nil, :web, {class_name: instrumentation_scope, name: "#{method} #{path}"})
            else
              original_name
            end
          end
        end
      end
    end
  end
end
