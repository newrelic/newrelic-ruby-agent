# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/utilization_data'

module NewRelic::Agent
  class UtilizationDataTest < Minitest::Test
    def test_aws_information_is_included_when_available
      AWSInfo.any_instance.stubs(:instance_id).returns("i-e7e85ce1")
      AWSInfo.any_instance.stubs(:instance_type).returns("m3.medium")
      AWSInfo.any_instance.stubs(:availability_zone).returns("us-west-2b")

      utilization_data = UtilizationData.new

      expected = {
        :aws => {
          :id => "i-e7e85ce1",
          :type => "m3.medium",
          :zone => "us-west-2b"
        }
      }

      assert_equal expected, utilization_data.to_collector_hash[:vendors]
    end

    def test_docker_information_is_included_when_available
      utilization_data = UtilizationData.new
      utilization_data.stubs(:container_id).returns("47cbd16b77c50cbf71401")

      expected = {
        :docker => {
          :id => "47cbd16b77c50cbf71401"
        }
      }

      assert_equal expected, utilization_data.to_collector_hash[:vendors]
    end

    def test_vendor_information_is_omitted_if_unavailable
      AWSInfo.any_instance.stubs(:instance_id).returns(nil)
      AWSInfo.any_instance.stubs(:instance_type).returns(nil)
      AWSInfo.any_instance.stubs(:availability_zone).returns(nil)
      utilization_data = UtilizationData.new

      assert_nil utilization_data.to_collector_hash[:vendors]
    end
  end
end