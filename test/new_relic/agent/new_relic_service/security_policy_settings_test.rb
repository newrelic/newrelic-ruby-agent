# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require File.expand_path(File.join(File.dirname(__FILE__),'../../..','test_helper'))
require 'new_relic/agent/new_relic_service'

module NewRelic
  module Agent
    class NewRelicService
      class SecurityPolicySettingsTest < Minitest::Test
        def test_security_policies_for_connect
          security_policies = {
             "record_sql" => {"enabled" => true, "required" => false, "position" => 0},
             "custom_events" => {"enabled" => true, "required" => false, "position" => 3},
             "job_arguments" => {"enabled" => true, "required" => false, "position" => 7},
             "custom_parameters" => {"enabled" => true, "required" => false, "position" => 4},
             "attributes_include" => {"enabled" => true, "required" => false, "position" => 1},
             "message_parameters" => {"enabled" => true, "required" => false, "position" => 6},
             "allow_raw_exception_messages" => {"enabled" => true, "required" => false, "position" => 2},
             "custom_instrumentation_editor" => {"enabled" => true, "required" => false, "position" => 5}
           }

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

           policies = SecurityPolicySettings.new(security_policies)

           assert_equal expected, policies.for_connect
        end
      end
    end
  end
end
