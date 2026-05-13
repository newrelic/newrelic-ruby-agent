# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class AttributeTranslatorTest < Minitest::Test
        def test_selects_datastore_translator_by_instrumentation_scope
          # opentelemetry-instrumentation-pg spans created by the
          # connect method don't have the db.system attribute on span start.
          # By using the instrumentation scope to identify
          # the appropriate translator, we can translate the datastore
          # attributes when they're provided later on in the span's lifecycle.
          result = AttributeTranslator.translate(
            instrumentation_scope: 'opentelemetry-instrumentation-pg',
            attributes: {},
            span_kind: :client,
            name: 'connect'
          )

          assert_same DatastoreTranslator, result[:translator]
        end

        def test_selects_datastore_translator_by_discriminating_attribute_db_system
          result = AttributeTranslator.translate(
            attributes: {'db.system' => 'postgresql'},
            span_kind: :client,
            name: 'SELECT'
          )

          assert_same DatastoreTranslator, result[:translator]
        end

        def test_selects_datastore_translator_by_discriminating_attribute_db_system_name
          result = AttributeTranslator.translate(
            attributes: {'db.system.name' => 'mysql'},
            span_kind: :client,
            name: 'SELECT'
          )

          assert_same DatastoreTranslator, result[:translator]
        end

        def test_discriminating_attribute_takes_precedence_over_span_kind
          # :client span_kind maps to HttpClientTranslator,
          # but db.system discriminating attribute should win
          result = AttributeTranslator.translate(
            attributes: {'db.system' => 'redis'},
            span_kind: :client,
            name: 'SELECT'
          )

          assert_same RedisDatastoreTranslator, result[:translator]
        end

        def test_non_specific_db_routes_to_generic_datastore_translator
          result = AttributeTranslator.translate(
            attributes: {'db.system' => 'some_database'},
            span_kind: :client,
            name: 'SELECT'
          )

          assert_same DatastoreTranslator, result[:translator]
        end

        def test_redis_instrumentation_scope_routes_to_redis_translator
          result = AttributeTranslator.translate(
            instrumentation_scope: 'opentelemetry-instrumentation-redis',
            attributes: {},
            span_kind: :client,
            name: 'GET'
          )

          assert_same RedisDatastoreTranslator, result[:translator]
        end

        def test_selects_http_client_translator_by_span_kind_client
          result = AttributeTranslator.translate(
            span_kind: :client,
            attributes: {}
          )

          assert_same HttpClientTranslator, result[:translator]
        end

        def test_selects_http_server_translator_by_span_kind_server
          result = AttributeTranslator.translate(
            span_kind: :server,
            attributes: {}
          )

          assert_same HttpServerTranslator, result[:translator]
        end

        def test_selects_generic_translator_by_span_kind_internal
          result = AttributeTranslator.translate(
            span_kind: :internal,
            attributes: {}
          )

          assert_same GenericTranslator, result[:translator]
        end

        def test_defaults_to_generic_translator_with_nil_span_kind
          result = AttributeTranslator.translate(
            span_kind: nil,
            attributes: {}
          )

          assert_same GenericTranslator, result[:translator]
        end

        def test_defaults_to_generic_translator_with_unknown_span_kind
          result = AttributeTranslator.translate(
            span_kind: :unknown,
            attributes: {}
          )

          assert_same GenericTranslator, result[:translator]
        end

        def test_handles_nil_attributes
          result = AttributeTranslator.translate(
            span_kind: :client,
            attributes: nil
          )

          assert_same HttpClientTranslator, result[:translator]
        end

        def test_returns_hash_with_expected_keys
          result = AttributeTranslator.translate(span_kind: :internal, attributes: {})

          assert result.key?(:intrinsic)
          assert result.key?(:agent)
          assert result.key?(:custom)
          assert result.key?(:for_segment_api)
          assert result.key?(:instance_variable)
          assert result.key?(:translator)
        end

        def test_unrecognized_attributes_become_custom
          attrs = {'custom.key' => 'custom_value', 'another.key' => 42}
          result = AttributeTranslator.translate(span_kind: :internal, attributes: attrs)

          assert_equal 'custom_value', result[:custom]['custom.key']
          assert_equal 42, result[:custom]['another.key']
        end
      end
    end
  end
end
