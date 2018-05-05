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
        def test_preliminary_settings
          policies = {
            "record_sql" => {"enabled" => false, "required" => false, "position" => 0},
            "custom_events" => {"enabled" => false, "required" => false, "position" => 3},
            "job_arguments" => {"enabled" => false, "required" => false, "position" => 7},
            "custom_parameters" => {"enabled" => false, "required" => false, "position" => 4},
            "attributes_include" => {"enabled" => false, "required" => false, "position" => 1},
            "message_parameters" => {"enabled" => false, "required" => false, "position" => 6},
            "allow_raw_exception_messages" => {"enabled" => false, "required" => false, "position" => 2},
            "custom_instrumentation_editor" => {"enabled" => false, "required" => false, "position" => 5}
          }

          expected = {
            "security_policies" => {
              "record_sql" => {"enabled" => false},
              "custom_events" => {"enabled" => false},
              "job_arguments" => {"enabled" => false},
              "custom_parameters" => {"enabled" => false},
              "attributes_include" => {"enabled" => false},
              "message_parameters" => {"enabled" => false},
              "allow_raw_exception_messages" => {"enabled" => false},
              "custom_instrumentation_editor" => {"enabled" => false}
            }
          }

          settings = SecurityPolicySettings.preliminary_settings(policies)

          assert_equal expected, settings
        end

        load_cross_agent_test("language_agents_security_policies").each do |test_case|
          define_method("test_#{test_case['name']}".tr(" ", "_")) do
            with_redefined_policies(test_case['required_features']) do
              policies = test_case['security_policies']
              validator = SecurityPolicySettings::Validator.new(test_case)

              if test_case['should_shutdown']
                assert_raises(NewRelic::Agent::UnrecoverableAgentException) do
                  validator.validate_matching_agent_config!
                end
              else
                validator.validate_matching_agent_config!
                settings = SecurityPolicySettings.preliminary_settings(policies)
                assert_equal test_case['expected_connect_policies'], settings['security_policies']
                test_case['validate_policies_not_in_connect'].keys.each do |key|
                  refute_includes settings['security_policies'].keys, key
                end
              end
            end
          end
        end

        def with_redefined_policies(new_policies)
          original_policies = SecurityPolicySettings::EXPECTED_SECURITY_POLICIES
          SecurityPolicySettings.send(:remove_const, :EXPECTED_SECURITY_POLICIES)
          SecurityPolicySettings.const_set(:EXPECTED_SECURITY_POLICIES, new_policies)
          yield
          SecurityPolicySettings.send(:remove_const, :EXPECTED_SECURITY_POLICIES)
          SecurityPolicySettings.const_set(:EXPECTED_SECURITY_POLICIES, original_policies)
        end
      end
    end
  end
end
