# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/utilization/gcp'

module NewRelic
  module Agent
    module Utilization
      class GCPTest < Minitest::Test
        def setup
          @vendor = GCP.new
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_generates_expected_collector_hash_for_valid_response
          fixture = File.read File.join(gcp_fixture_path, "valid.json")

          stubbed_response = stub(code: '200', body: fixture)
          @vendor.stubs(:request_metadata).returns(stubbed_response)

          expected = {
            :id => "4332984205593314925",
            :machineType => "custom-1-1024",
            :name => "aef-default-20170714t143150-1q67",
            :zone => "us-central1-b"
          }

          assert @vendor.detect
          assert_equal expected, @vendor.metadata
        end

        def test_fails_when_response_contains_invalid_chars
          fixture = File.read File.join(gcp_fixture_path, "invalid_chars.json")

          stubbed_response = stub(code: '200', body: fixture)
          @vendor.stubs(:request_metadata).returns(stubbed_response)

          refute @vendor.detect
          assert_metrics_recorded "Supportability/utilization/gcp/error" => {:call_count => 1}
        end

        def test_fails_when_response_is_missing_required_value
          fixture = File.read File.join(gcp_fixture_path, "missing_value.json")

          stubbed_response = stub(code: '200', body: fixture)
          @vendor.stubs(:request_metadata).returns(stubbed_response)

          refute @vendor.detect
          assert_metrics_recorded "Supportability/utilization/gcp/error" => {:call_count => 1}
        end

        def test_fails_based_on_response_code
          fixture = File.read File.join(gcp_fixture_path, "valid.json")

          stubbed_response = stub(code: '404', body: fixture)
          @vendor.stubs(:request_metadata).returns(stubbed_response)

          refute @vendor.detect
          refute_metrics_recorded "Supportability/utilization/gcp/error"
        end

        def gcp_fixture_path
          File.expand_path('../../../../fixtures/utilization/gcp', __FILE__)
        end
      end
    end
  end
end
