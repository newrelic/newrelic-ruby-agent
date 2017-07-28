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

        def test_generates_expected_collector_hash_for_valid_response
          fixture = File.read File.join(aws_fixture_path, "valid.json")

          mock_response = mock(code: '200', body: fixture)
          @vendor.stubs(:request_metadata).returns(mock_response)

          expected = {
            :instanceId => "i-08987cdeff7489fa7",
            :instanceType => "c4.2xlarge",
            :availabilityZone => "us-west-2c"
          }

          assert @vendor.detect
          assert_equal expected, @vendor.metadata
        end

        def test_fails_when_response_contains_invalid_chars
          fixture = File.read File.join(aws_fixture_path, "invalid_chars.json")

          mock_response = mock(code: '200', body: fixture)
          @vendor.stubs(:request_metadata).returns(mock_response)

          refute @vendor.detect
          assert_metrics_recorded "Supportability/utilization/aws/error" => {:call_count => 1}
        end

        def test_fails_when_response_is_missing_required_value
          fixture = File.read File.join(aws_fixture_path, "missing_value.json")

          mock_response = mock(code: '200', body: fixture)
          @vendor.stubs(:request_metadata).returns(mock_response)

          refute @vendor.detect
          assert_metrics_recorded "Supportability/utilization/aws/error" => {:call_count => 1}
        end

        def test_fails_based_on_response_code
          fixture = File.read File.join(aws_fixture_path, "valid.json")

          mock_response = stub(code: '404', body: fixture)
          @vendor.stubs(:request_metadata).returns(mock_response)

          refute @vendor.detect
          refute_metrics_recorded "Supportability/utilization/aws/error"
        end

        def aws_fixture_path
          File.expand_path('../../../../fixtures/utilization/aws', __FILE__)
        end
      end
    end
  end
end
