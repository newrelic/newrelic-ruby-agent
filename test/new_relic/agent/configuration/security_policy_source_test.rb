# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/configuration/security_policy_source'

module NewRelic
  module Agent
    module Configuration
      class SecurityPolicySourceTest < Minitest::Test
        def test_record_sql_enabled
          policies = generate_security_policies(default: false, enabled: ['record_sql'])

          with_config(:'transaction_tracer.record_sql' => 'raw',
            :'slow_sql.record_sql'           => 'raw',
            :'mongo.capture_queries'         => true,
            :'mongo.obfuscate_queries'       => false) do
            source = SecurityPolicySource.new(policies)

            assert_equal 'obfuscated', source[:'transaction_tracer.record_sql']
            assert_equal 'obfuscated', source[:'slow_sql.record_sql']
            assert source[:'mongo.obfuscate_queries']
          end
        end

        def test_record_sql_disabled
          policies = generate_security_policies(default: true, disabled: ['record_sql'])

          with_config(:'transaction_tracer.record_sql' => 'raw',
            :'slow_sql.record_sql'           => 'raw',
            :'mongo.capture_queries'         => true) do
            source = SecurityPolicySource.new(policies)

            assert_equal 'off', source[:'transaction_tracer.record_sql']
            assert_equal 'off', source[:'slow_sql.record_sql']
            refute source[:'mongo.capture_queries']
          end
        end

        def test_record_sql_enabled_elasticsearch
          policies = generate_security_policies(default: false, enabled: ['record_sql'])

          with_config(:'transaction_tracer.record_sql' => 'raw',
            :'slow_sql.record_sql' => 'raw',
            :'elasticsearch.capture_queries'         => true,
            :'elasticsearch.obfuscate_queries'       => false) do
            source = SecurityPolicySource.new(policies)

            assert_equal 'obfuscated', source[:'transaction_tracer.record_sql']
            assert_equal 'obfuscated', source[:'slow_sql.record_sql']
            assert source[:'elasticsearch.obfuscate_queries']
          end
        end

        def test_record_sql_disabled_elasticsearch
          policies = generate_security_policies(default: true, disabled: ['record_sql'])

          with_config(:'transaction_tracer.record_sql' => 'raw',
            :'slow_sql.record_sql' => 'raw',
            :'elasticsearch.capture_queries' => true) do
            source = SecurityPolicySource.new(policies)

            assert_equal 'off', source[:'transaction_tracer.record_sql']
            assert_equal 'off', source[:'slow_sql.record_sql']
            refute source[:'elasticsearch.capture_queries']
          end
        end

        def test_attributes_include_enabled
          policies = generate_security_policies(default: false, enabled: ['attributes_include'])
          with_config(:'attributes.include' => ['request.parameters.*'],
            :'transaction_tracer.attributes.include'     => ['request.uri'],
            :'transaction_events.attributes.include'     => ['request.headers.*'],
            :'error_collector.attributes.include'        => ['request.method'],
            :'browser_monitoring.attributes.include'     => ['http.statusCode'],
            :'span_events.attributes.include'            => ['http.url'],
            :'transaction_segments.attributes.include'   => ['sql_statement']) do
            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'attributes.include'
            refute_includes source.keys, :'transaction_tracer.attributes.include'
            refute_includes source.keys, :'transaction_events.attributes.include'
            refute_includes source.keys, :'error_collector.attributes.include'
            refute_includes source.keys, :'browser_monitoring.attributes.include'
            refute_includes source.keys, :'span_events.attributes.include'
            refute_includes source.keys, :'transaction_segments.attributes.include'
          end
        end

        def test_attributes_include_disabled
          policies = generate_security_policies(default: true, disabled: ['attributes_include'])
          with_config(:'attributes.include' => ['request.parameters.*'],
            :'transaction_tracer.attributes.include'     => ['request.uri'],
            :'transaction_events.attributes.include'     => ['request.headers.*'],
            :'error_collector.attributes.include'        => ['request.method'],
            :'browser_monitoring.attributes.include'     => ['http.statusCode'],
            :'span_events.attributes.include'            => ['http.url'],
            :'transaction_segments.attributes.include'   => ['sql_statement']) do
            source = SecurityPolicySource.new(policies)

            assert_empty(source[:'attributes.include'])
            assert_empty(source[:'transaction_tracer.attributes.include'])
            assert_empty(source[:'transaction_events.attributes.include'])
            assert_empty(source[:'error_collector.attributes.include'])
            assert_empty(source[:'browser_monitoring.attributes.include'])
            assert_empty(source[:'span_events.attributes.include'])
            assert_empty(source[:'transaction_segments.attributes.include'])
          end
        end

        def test_allow_raw_exception_messages_enabled
          policies = generate_security_policies(default: false, enabled: ['allow_raw_exception_messages'])
          with_config(:'strip_exception_messages.enabled' => true) do
            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'strip_exception_messages'
          end
        end

        def test_allow_raw_exception_messages_disabled
          policies = generate_security_policies(default: true, disabled: ['allow_raw_exception_messages'])
          with_config(:'strip_exception_messages.enabled' => true) do
            source = SecurityPolicySource.new(policies)

            refute source[:'strip_exception_messages.enabled']
          end
        end

        def test_custom_events_enabled
          policies = generate_security_policies(default: false, enabled: ['custom_events'])
          with_config(:'custom_insights_events.enabled' => true) do
            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'custom_insights_events.enabled'
          end
        end

        def test_custom_events_disabled
          policies = generate_security_policies(default: true, disabled: ['custom_events'])
          with_config(:'custom_insights_events.enabled' => true) do
            source = SecurityPolicySource.new(policies)

            refute source[:'custom_insights_events.enabled']
          end
        end

        def test_custom_instrumentation_editor_enabled
          policies = generate_security_policies(default: false, enabled: ['custom_instrumentation_editor'])
          source = SecurityPolicySource.new(policies)

          refute_includes source.keys, :'custom_instrumentation_editor.enabled'
        end

        def test_custom_instrumentation_editor_disabled
          policies = generate_security_policies(default: true, disabled: ['custom_instrumentation_editor'])
          source = SecurityPolicySource.new(policies)

          refute_includes source.keys, :'custom_instrumentation_editor.enabled'
        end

        def test_message_parameters_enabled
          policies = generate_security_policies(default: false, enabled: ['message_parameters'])
          with_config(:'message_tracer.segment_parameters.enabled' => true) do
            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'message_tracer.segment_parameters.enabled'
          end
        end

        def test_message_parameters_disabled
          policies = generate_security_policies(default: true, disabled: ['message_parameters'])
          with_config(:'message_tracer.segment_parameters.enabled' => true) do
            source = SecurityPolicySource.new(policies)

            refute source[:'message_tracer.segment_parameters.enabled']
          end
        end

        def generate_security_policies(default: false, enabled: [], disabled: [], required: [])
          policies = {
            "record_sql" => {"enabled" => default, "required" => false, "position" => 0},
            "custom_events" => {"enabled" => default, "required" => false, "position" => 3},
            "custom_parameters" => {"enabled" => default, "required" => false, "position" => 4},
            "attributes_include" => {"enabled" => default, "required" => false, "position" => 1},
            "message_parameters" => {"enabled" => default, "required" => false, "position" => 6},
            "allow_raw_exception_messages" => {"enabled" => default, "required" => false, "position" => 2},
            "custom_instrumentation_editor" => {"enabled" => default, "required" => false, "position" => 5}
          }

          enabled.each { |name| policies[name]["enabled"] = true }
          disabled.each { |name| policies[name]["enabled"] = false }
          required.each { |name| policies[name]["required"] = true }

          policies
        end
      end
    end
  end
end
