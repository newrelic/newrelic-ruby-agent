# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'translators/datastore_translator'
require_relative 'translators/http_client_translator'
require_relative 'translators/http_server_translator'
require_relative 'translators/generic_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class AttributeTranslator
        TRANSLATOR_REGISTRY = {
          # Only use the instrumentation_scope category for scopes that
          # will not be correctly assigned using discriminating attributes
          # or span kind
          instrumentation_scope: {
            # pg instrumentation doesn't have db.system assigned when connect
            # spans start, so they would be incorrectly assigned
            # the HttpClientTranslator
            'opentelemetry-instrumentation-pg' => DatastoreTranslator,
            'opentelemetry-instrumentation-mysql2' => DatastoreTranslator
            # 'opentelemetry-instrumentation-grpc' => RpcTranslator,
            # 'opentelemetry-instrumentation-redis' => RedisDatastoreTranslator,
          },
          discriminating_attribute: {
            'db.system' => DatastoreTranslator,
            'db.system.name' => DatastoreTranslator
            # 'messaging.system' => MessagingTranslator,
            # 'rpc.system' => RpcTranslator,
          },
          span_kind: {
            client: HttpClientTranslator,
            server: HttpServerTranslator,
            # consumer: MessagingConsumerTranslator,
            # producer: MessagingProducerTranslator,
            internal: GenericTranslator
          }
        }.freeze

        DISCRIMINATING_ATTRIBUTE_KEYS = TRANSLATOR_REGISTRY[:discriminating_attribute].keys.freeze

        # Identify the appropriate translator based on the provided arguments.
        # Then, call that translator's translate method.
        # The translator can be identified by instrumentation scope,
        # distinguising attributes, or span kind.
        #
        # @params span_kind [optional Symbol] the span kind of the span to translate
        # @params attributes [optional Hash] the attributes on the span to translate
        # @params instrumentation_scope [optional String] the instrumentation scope of the span to translate
        # @params name [optional String] the name of the span to translate. This isn't used
        #   to determine what translator should be used, but it may be used by the translators
        #   for New Relic attributes.
        #
        # @return [Hash] hash with translated attributes, created by the dispatched translator
        def self.translate(span_kind: nil, attributes: nil, instrumentation_scope: nil, name: nil)
          attributes ||= NewRelic::EMPTY_HASH
          translator =
            if TRANSLATOR_REGISTRY[:instrumentation_scope][instrumentation_scope]
              TRANSLATOR_REGISTRY[:instrumentation_scope][instrumentation_scope]
            elsif k = DISCRIMINATING_ATTRIBUTE_KEYS.find { |key| attributes.key?(key) }
              TRANSLATOR_REGISTRY[:discriminating_attribute][k]
            elsif TRANSLATOR_REGISTRY[:span_kind][span_kind]
              TRANSLATOR_REGISTRY[:span_kind][span_kind]
            else
              GenericTranslator
            end

          # TODO: Decide if we want instances or not
          translator.new.translate(attributes: attributes, name: name, instrumentation_scope: instrumentation_scope)
        end
      end
    end
  end
end
