# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/utilization/aws'

module NewRelic
  module Agent
    module Utilization
      class AWSTest < Minitest::Test
        def setup
          @vendor = AWS.new
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_generates_expected_collector_hash
          fixture = File.read aws_fixture_path

          mock_response = mock(code: '200', body: fixture)
          @vendor.stubs(:request_metadata).returns(mock_response)

          expected = {"aws" => {
              "instanceId" => "i-08987cdeff7489fa7",
              "instanceType" => "c4.2xlarge",
              "availabilityZone" => "us-west-2c"
            }
          }

          assert @vendor.detect
          assert_equal expected, @vendor.to_collector_hash
        end

        def aws_fixture_path
          File.expand_path('../../../../fixtures/utilization/aws.json', __FILE__)
        end
      end
    end
  end
end
