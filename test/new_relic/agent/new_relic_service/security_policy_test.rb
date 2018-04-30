# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require File.expand_path(File.join(File.dirname(__FILE__),'../../..','test_helper'))
require 'new_relic/agent/new_relic_service/security_policy_settings'

module NewRelic
  module Agent
    class NewRelicService
      class SecurityPolicyTest < Minitest::Test
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
            "record_sql" => {"enabled" => false},
            "custom_events" => {"enabled" => false},
            "job_arguments" => {"enabled" => false},
            "custom_parameters" => {"enabled" => false},
            "attributes_include" => {"enabled" => false},
            "message_parameters" => {"enabled" => false},
            "allow_raw_exception_messages" => {"enabled" => false},
            "custom_instrumentation_editor" => {"enabled" => false}
          }

          policies = SecurityPolicy.preliminary_settings(policies)

          assert_equal expected, policies
        end
      end
    end
  end
end
