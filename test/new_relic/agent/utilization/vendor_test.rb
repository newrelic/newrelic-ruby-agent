# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class VendorTest < Minitest::Test
        class ExampleVendor < Vendor
          provider_name "example"
          endpoint "http://http://169.254.169.254/metadata"
          headers "meta" => "yes"
          keys ["vm_type", "vm_id", "vm_zone"]
        end

        def setup
          @vendor = ExampleVendor.new
        end

        def test_has_name
          assert_equal "example", @vendor.provider_name
        end

        def test_has_endpoint
          assert_equal URI("http://http://169.254.169.254/metadata"), @vendor.endpoint
        end

        def test_has_headers
          expected = {"meta" => "yes"}
          assert_equal expected, @vendor.headers
        end

        def test_assigns_expected_keys
          mock_response = mock(:code => '200', :body => '{"vm_type":"large","vm_id":"x123", "vm_zone":"danger_zone", "whatever":"nothing"}')
          @vendor.stubs(:request_metadata).returns(mock_response)
          @vendor.process

          expected = {
            "example" => {
              "vm_type" => "large",
              "vm_id" => "x123",
              "vm_zone" => "danger_zone"
            }
          }

          assert_equal expected, @vendor.to_collector_hash
        end
      end
    end
  end
end
