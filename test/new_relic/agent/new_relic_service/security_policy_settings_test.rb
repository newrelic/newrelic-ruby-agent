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

          with_config(:'transaction_tracer.record_sql' => 'raw',
                      :'slow_sql.record_sql'           => 'raw',
                      :'mongo.capture_queries'         => true,
                      :'mongo.obfuscate_queries'       => false) do

            settings = SecurityPolicySettings.new(policies).for_lasp_source

            assert_equal 'obfuscated', settings[:'transaction_tracer.record_sql']
            assert_equal 'obfuscated', settings[:'slow_sql.record_sql']
            assert_equal true, settings[:'mongo.obfuscate_queries']
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
