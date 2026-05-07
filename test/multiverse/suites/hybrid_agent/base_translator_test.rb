# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class BaseTranslatorTest < Minitest::Test
        # HttpClientTranslator has a mix of :intrinsic and :instance_variable
        # categories alongside segment_field mappings, making it a good
        # candidate for testing BaseTranslator#translate routing.
        def http_client_translator
          HttpClientTranslator
        end

        # HttpServerTranslator has :agent and :instance_variable categories.
        def http_server_translator
          HttpServerTranslator
        end

        def test_translate_routes_intrinsic_attributes
          attrs = {'server.address' => 'example.com', 'server.port' => 443}
          result = http_client_translator.translate(attributes: attrs)

          assert_equal 'example.com', result[:intrinsic]['host']
          assert_equal 443, result[:intrinsic]['port']
        end

        def test_translate_routes_agent_attributes
          attrs = {
            'url.path' => '/api/users',
            'http.request.method' => 'GET'
          }
          result = http_server_translator.translate(attributes: attrs)

          assert_equal '/api/users', result[:agent]['request.uri'][:value]
          assert_equal 'GET', result[:agent]['request.method'][:value]
        end

        def test_agent_attributes_include_destinations
          attrs = {'url.path' => '/path'}
          result = http_server_translator.translate(attributes: attrs)
          default_destinations = NewRelic::Agent::OpenTelemetry::AttributeMappings::DEFAULT_DESTINATIONS

          assert result[:agent]['request.uri'].key?(:destinations)
          assert_equal default_destinations, result[:agent]['request.uri'][:destinations]
        end

        def test_translate_routes_instance_variable_attributes
          attrs = {'http.response.status_code' => 200}
          result = http_client_translator.translate(attributes: attrs)

          assert_equal 200, result[:instance_variable]['http_status_code']
        end

        def test_translate_routes_segment_field_attributes
          attrs = {'http.request.method' => 'POST'}
          result = http_client_translator.translate(attributes: attrs)

          assert_equal 'POST', result[:for_segment_api][:procedure]
        end

        def test_translate_puts_unmapped_attributes_in_custom
          attrs = {
            'server.address' => 'example.com',
            'custom.attribute' => 'custom_value',
            'another.unmapped' => 42
          }
          result = http_client_translator.translate(attributes: attrs)

          assert_equal 'custom_value', result[:custom]['custom.attribute']
          assert_equal 42, result[:custom]['another.unmapped']
          refute result[:custom].key?('server.address'), 'mapped attributes should not appear in custom'
        end

        def test_translate_does_not_include_mapped_keys_in_custom
          attrs = {
            'http.response.status_code' => 404,
            'http.request.method' => 'DELETE',
            'server.address' => 'example.com',
            'server.port' => 80,
            'url.full' => 'https://example.com/api'
          }
          result = http_client_translator.translate(attributes: attrs)

          mapped_keys = %w[http.response.status_code http.request.method server.address server.port url.full]

          assert_empty result[:custom].keys & mapped_keys
        end

        def test_translate_handles_empty_attributes
          result = http_client_translator.translate(attributes: {})

          assert_empty result[:intrinsic]
          assert_empty result[:agent]
          assert_empty result[:instance_variable]
          assert_empty result[:for_segment_api]
          assert_empty result[:custom]
        end

        def test_translate_returns_translator_class
          result = http_client_translator.translate(attributes: {})

          assert_same HttpClientTranslator, result[:translator]
        end

        def test_translate_uses_first_present_otel_key
          # v1.23 stable key 'server.address' should be used over
          # v1.17 old key 'net.peer.name' when both are present
          attrs = {
            'server.address' => 'stable.example.com',
            'net.peer.name' => 'old.example.com'
          }
          result = http_client_translator.translate(attributes: attrs)

          assert_equal 'stable.example.com', result[:intrinsic]['host']
        end

        def test_translate_falls_back_to_second_otel_key_when_first_absent
          attrs = {'net.peer.name' => 'old.example.com'}
          result = http_client_translator.translate(attributes: attrs)

          assert_equal 'old.example.com', result[:intrinsic]['host']
        end

        def test_translate_does_not_mutate_original_attributes
          attrs = {'server.address' => 'example.com', 'custom.key' => 'value'}
          original_keys = attrs.keys.dup

          http_client_translator.translate(attributes: attrs)

          assert_equal original_keys.sort, attrs.keys.sort
        end

        def test_generic_translator_puts_all_attributes_in_custom
          attrs = {'any.key' => 'any_value', 'another' => 123}
          result = GenericTranslator.translate(attributes: attrs)

          assert_empty result[:intrinsic]
          assert_empty result[:agent]
          assert_empty result[:instance_variable]
          assert_empty result[:for_segment_api]
          assert_equal attrs, result[:custom]
        end
      end
    end
  end
end
