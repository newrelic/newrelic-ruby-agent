# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require File.expand_path(File.join(File.dirname(__FILE__),'../../..','test_helper'))
require 'new_relic/agent/new_relic_service/security_policy_settings'

module NewRelic
  module Agent
    class NewRelicService
      class SecurityPolicySettingsTest < Minitest::Test
        def test_security_policies_for_connect
          policies = generate_security_policies(default: true)

          expected = {
            "record_sql" => {"enabled" => true},
            "custom_events" => {"enabled" => true},
            "job_arguments" => {"enabled" => true},
            "custom_parameters" => {"enabled" => true},
            "attributes_include" => {"enabled" => true},
            "message_parameters" => {"enabled" => true},
            "allow_raw_exception_messages" => {"enabled" => true},
            "custom_instrumentation_editor" => {"enabled" => true}
          }

          policies = SecurityPolicySettings.new(policies)

          assert_equal expected, policies.for_connect
        end

        def test_for_lasp_source_record_sql_enabled
          policies = generate_security_policies(default: false, enabled: ['record_sql'])

          with_config :'transaction_tracer.record_sql' => 'raw',
                      :'slow_sql.record_sql'           => 'raw',
                      :'mongo.capture_queries'         => true,
                      :'mongo.obfuscate_queries'       => false do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal 'obfuscated', settings[:'transaction_tracer.record_sql']
            assert_equal 'obfuscated', settings[:'slow_sql.record_sql']
            assert_equal true, settings[:'mongo.obfuscate_queries']
          end
        end

        def test_for_lasp_source_record_sql_disabled
          policies = generate_security_policies(default: true, disabled: ['record_sql'])

          with_config :'transaction_tracer.record_sql' => 'raw',
                      :'slow_sql.record_sql'           => 'raw',
                      :'mongo.capture_queries'         => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal 'off', settings[:'transaction_tracer.record_sql']
            assert_equal 'off', settings[:'slow_sql.record_sql']
            assert_equal false, settings[:'mongo.capture_queries']
          end
        end

        def test_for_lasp_source_attributes_include_enabled
          policies = generate_security_policies(default: false, enabled: ['attributes_include'])
          with_config :'attributes.include'                        => ['request.parameters.*'],
                      :'transaction_tracer.attributes.include'     => ['request.uri'],
                      :'transaction_events.attributes.include'     => ['request.headers.*'],
                      :'error_collector.attributes.include'        => ['request.method'],
                      :'browser_monitoring.attributes.include'     => ['httpResponseCode'] do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            refute_includes settings.keys, :'attributes.include'
            refute_includes settings.keys, :'transaction_tracer.attributes.include'
            refute_includes settings.keys, :'transaction_events.attributes.include'
            refute_includes settings.keys, :'error_collector.attributes.include'
            refute_includes settings.keys, :'browser_monitoring.attributes.include'
          end
        end

        def test_for_lasp_source_attributes_include_disabled
          policies = generate_security_policies(default: true, disabled: ['attributes_include'])
          with_config :'attributes.include'                        => ['request.parameters.*'],
                      :'transaction_tracer.attributes.include'     => ['request.uri'],
                      :'transaction_events.attributes.include'     => ['request.headers.*'],
                      :'error_collector.attributes.include'        => ['request.method'],
                      :'browser_monitoring.attributes.include'     => ['httpResponseCode'] do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal [], settings[:'attributes.include']
            assert_equal [], settings[:'transaction_tracer.attributes.include']
            assert_equal [], settings[:'transaction_events.attributes.include']
            assert_equal [], settings[:'error_collector.attributes.include']
            assert_equal [], settings[:'browser_monitoring.attributes.include']
          end
        end

        def test_for_lasp_source_allow_raw_exception_messages_enabled
          policies = generate_security_policies(default: false, enabled: ['allow_raw_exception_messages'])
          with_config :'strip_exception_messages.enabled' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            refute_includes settings, :'strip_exception_messages'
          end
        end

        def test_for_lasp_source_allow_raw_exception_messages_disabled
          policies = generate_security_policies(default: true, disabled: ['allow_raw_exception_messages'])
          with_config :'strip_exception_messages.enabled' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal false, settings[:'strip_exception_messages.enabled']
          end
        end

        def test_for_lasp_source_custom_events_enabled
          policies = generate_security_policies(default: false, enabled: ['custom_events'])
          with_config :'custom_insights_events.enabled' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            refute_includes settings, :'custom_insights_events.enabled'
          end
        end

        def test_for_lasp_source_custom_events_disabled
          policies = generate_security_policies(default: true, disabled: ['custom_events'])
          with_config :'custom_insights_events.enabled' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal false, settings[:'custom_insights_events.enabled']
          end
        end

        def test_for_lasp_source_custom_instrumentation_editor_enabled
          policies = generate_security_policies(default: false, enabled: ['custom_instrumentation_editor'])
          settings = SecurityPolicySettings.new(policies).for_lasp_source

          refute_includes settings, :'custom_instrumentation_editor.enabled'
        end

        def test_for_lasp_source_custom_instrumentation_editor_disabled
          policies = generate_security_policies(default: true, disabled: ['custom_instrumentation_editor'])
          settings = SecurityPolicySettings.new(policies).for_lasp_source

          refute_includes settings, :'custom_instrumentation_editor.enabled'
        end

        def test_for_lasp_source_message_parameters_enabled
          policies = generate_security_policies(default: false, enabled: ['message_parameters'])
          with_config :'message_tracer.segment_parameters.enabled' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            refute_includes settings, :'message_tracer.segment_parameters.enabled'
          end
        end

        def test_for_lasp_source_message_parameters_disabled
          policies = generate_security_policies(default: true, disabled: ['message_parameters'])
          with_config :'message_tracer.segment_parameters.enabled' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal false, settings[:'message_tracer.segment_parameters.enabled']
          end
        end

        def test_for_lasp_source_job_arguments_enabled
          policies = generate_security_policies(default: false, enabled: ['job_arguments'])
          with_config :'resque.capture_params'  => true,
                      :'sidekiq.capture_params' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            refute_includes settings, :'resque.capture_params'
            refute_includes settings, :'sidekiq.capture_params'
          end
        end

        def test_for_lasp_source_job_arguments_disabled
          policies = generate_security_policies(default: true, disabled: ['job_arguments'])
          with_config :'resque.capture_params'  => true,
                      :'sidekiq.capture_params' => true do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal false, settings[:'resque.capture_params']
            assert_equal false, settings[:'sidekiq.capture_params']
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
