# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class VendorTest < Minitest::Test
        class ExampleVendor < Vendor
          vendor_name "example"
          endpoint "http://http://169.254.169.254/metadata"
          headers "meta" => "yes"
          keys ["vm_type", "vm_id", "vm_zone"]
          key_transforms :to_sym
        end

        def setup
          @vendor = ExampleVendor.new
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_has_name
          assert_equal "example", @vendor.vendor_name
        end

        def test_has_endpoint
          assert_equal URI("http://http://169.254.169.254/metadata"), @vendor.endpoint
        end

        def test_has_headers
          expected = {"meta" => "yes"}
          assert_equal expected, @vendor.headers
        end

        def test_assigns_expected_keys
          stubbed_response = stub(:code => '200', :body => '{"vm_type":"large","vm_id":"x123", "vm_zone":"danger_zone", "whatever":"nothing"}')
          @vendor.stubs(:request_metadata).returns(stubbed_response)
          assert @vendor.detect

          expected = {
              :vm_type => "large",
              :vm_id => "x123",
              :vm_zone => "danger_zone"
          }

          assert_equal expected, @vendor.metadata
        end

        def test_detect_fails_when_expected_field_is_null
          stubbed_response = stub(:code => '200', :body => '{"vm_type":"large","vm_id":"x123", "vm_zone":null}')
          @vendor.stubs(:request_metadata).returns(stubbed_response)

          refute @vendor.detect
          assert_metrics_recorded "Supportability/utilization/example/error" => {:call_count => 1}
        end

        def test_detect_fails_when_expected_field_has_invalid_chars
          stubbed_response = stub(:code => '200', :body => '{"vm_type":"large","vm_id":"x123", "vm_zone":"*star*is*invalid*"}')
          @vendor.stubs(:request_metadata).returns(stubbed_response)

          refute @vendor.detect
          assert_metrics_recorded "Supportability/utilization/example/error" => {:call_count => 1}
        end
      end
    end
  end
end
