# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require File.expand_path(File.join(File.dirname(__FILE__),'../../..','test_helper'))
require 'new_relic/agent/configuration/security_policy_source'

module NewRelic
  module Agent
    module Configuration
      class SecurityPolicySourceTest < Minitest::Test
        def test_record_sql_enabled
          policies = generate_security_policies(default: false, enabled: ['record_sql'])

          with_config :'transaction_tracer.record_sql' => 'raw',
                      :'slow_sql.record_sql'           => 'raw',
                      :'mongo.capture_queries'         => true,
                      :'mongo.obfuscate_queries'       => false do

            source = SecurityPolicySource.new(policies)

            assert_equal 'obfuscated', source[:'transaction_tracer.record_sql']
            assert_equal 'obfuscated', source[:'slow_sql.record_sql']
            assert_equal true, source[:'mongo.obfuscate_queries']
          end
        end

        def test_record_sql_disabled
          policies = generate_security_policies(default: true, disabled: ['record_sql'])

          with_config :'transaction_tracer.record_sql' => 'raw',
                      :'slow_sql.record_sql'           => 'raw',
                      :'mongo.capture_queries'         => true do

            source = SecurityPolicySource.new(policies)

            assert_equal 'off', source[:'transaction_tracer.record_sql']
            assert_equal 'off', source[:'slow_sql.record_sql']
            assert_equal false, source[:'mongo.capture_queries']
          end
        end

        def test_attributes_include_enabled
          policies = generate_security_policies(default: false, enabled: ['attributes_include'])
          with_config :'attributes.include'                        => ['request.parameters.*'],
                      :'transaction_tracer.attributes.include'     => ['request.uri'],
                      :'transaction_events.attributes.include'     => ['request.headers.*'],
                      :'error_collector.attributes.include'        => ['request.method'],
                      :'browser_monitoring.attributes.include'     => ['httpResponseCode'],
                      :'span_events.attributes.include'            => ['http.url'],
                      :'transaction_segments.attributes.include'   => ['sql_statement'] do

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
          with_config :'attributes.include'                        => ['request.parameters.*'],
                      :'transaction_tracer.attributes.include'     => ['request.uri'],
                      :'transaction_events.attributes.include'     => ['request.headers.*'],
                      :'error_collector.attributes.include'        => ['request.method'],
                      :'browser_monitoring.attributes.include'     => ['httpResponseCode'],
                      :'span_events.attributes.include'            => ['http.url'],
                      :'transaction_segments.attributes.include'   => ['sql_statement'] do

            source = SecurityPolicySource.new(policies)

            assert_equal [], source[:'attributes.include']
            assert_equal [], source[:'transaction_tracer.attributes.include']
            assert_equal [], source[:'transaction_events.attributes.include']
            assert_equal [], source[:'error_collector.attributes.include']
            assert_equal [], source[:'browser_monitoring.attributes.include']
            assert_equal [], source[:'span_events.attributes.include']
            assert_equal [], source[:'transaction_segments.attributes.include']
          end
        end

        def test_allow_raw_exception_messages_enabled
          policies = generate_security_policies(default: false, enabled: ['allow_raw_exception_messages'])
          with_config :'strip_exception_messages.enabled' => true do

            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'strip_exception_messages'
          end
        end

        def test_allow_raw_exception_messages_disabled
          policies = generate_security_policies(default: true, disabled: ['allow_raw_exception_messages'])
          with_config :'strip_exception_messages.enabled' => true do

            source = SecurityPolicySource.new(policies)

            assert_equal false, source[:'strip_exception_messages.enabled']
          end
        end

        def test_custom_events_enabled
          policies = generate_security_policies(default: false, enabled: ['custom_events'])
          with_config :'custom_insights_events.enabled' => true do

            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'custom_insights_events.enabled'
          end
        end

        def test_custom_events_disabled
          policies = generate_security_policies(default: true, disabled: ['custom_events'])
          with_config :'custom_insights_events.enabled' => true do

            source = SecurityPolicySource.new(policies)

            assert_equal false, source[:'custom_insights_events.enabled']
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
          with_config :'message_tracer.segment_parameters.enabled' => true do

            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'message_tracer.segment_parameters.enabled'
          end
        end

        def test_message_parameters_disabled
          policies = generate_security_policies(default: true, disabled: ['message_parameters'])
          with_config :'message_tracer.segment_parameters.enabled' => true do

            source = SecurityPolicySource.new(policies)

            assert_equal false, source[:'message_tracer.segment_parameters.enabled']
          end
        end

        def test_job_arguments_enabled
          policies = generate_security_policies(default: false, enabled: ['job_arguments'])
          with_config :'resque.capture_params'  => true,
                      :'sidekiq.capture_params' => true do

            source = SecurityPolicySource.new(policies)

            refute_includes source.keys, :'resque.capture_params'
            refute_includes source.keys, :'sidekiq.capture_params'
          end
        end

        def test_job_arguments_disabled
          policies = generate_security_policies(default: true, disabled: ['job_arguments'])
          with_config :'resque.capture_params'  => true,
                      :'sidekiq.capture_params' => true do

            source = SecurityPolicySource.new(policies)

            assert_equal false, source[:'resque.capture_params']
            assert_equal false, source[:'sidekiq.capture_params']
          end
        end

        def generate_security_policies(default: false, enabled: [], disabled: [], required: [])
          policies = {
            "record_sql" => {"enabled" => default, "required" => false, "position" => 0},
            "custom_events" => {"enabled" => default, "required" => false, "position" => 3},
            "job_arguments" => {"enabled" => default, "required" => false, "position" => 7},
            "custom_parameters" => {"enabled" => default, "required" => false, "position" => 4},
            "attributes_include" => {"enabled" => default, "required" => false, "position" => 1},
            "message_parameters" => {"enabled" => default, "required" => false, "position" => 6},
            "allow_raw_exception_messages" => {"enabled" => default, "required" => false, "position" => 2},
            "custom_instrumentation_editor" => {"enabled" => default, "required" => false, "position" => 5}
          }

          enabled.each  { |name| policies[name]["enabled"] = true }
          disabled.each { |name| policies[name]["enabled"] = false}
          required.each { |name| policies[name]["required"] = true}

          policies
        end
      end
    end
  end
end
