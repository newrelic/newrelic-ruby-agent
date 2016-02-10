# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/utilization_data'

module NewRelic::Agent
  class UtilizationDataTest < Minitest::Test
    def setup
      stub_aws_info
    end

    def test_aws_information_is_included_when_available
      stub_aws_info(
        :instance_id => "i-e7e85ce1",
        :instance_type => "m3.medium",
        :availability_zone => "us-west-2b"
      )

      utilization_data = UtilizationData.new

      expected = {
        :id => "i-e7e85ce1",
        :type => "m3.medium",
        :zone => "us-west-2b"
      }

      assert_equal expected, utilization_data.to_collector_hash[:vendors][:aws]
    end

    def test_aws_information_is_omitted_when_available_but_disabled_by_config
      stub_aws_info(
        :instance_id => "i-e7e85ce1",
        :instance_type => "m3.medium",
        :availability_zone => "us-west-2b"
      )

      with_config(:'utilization.detect_aws' => false, :'utilization.detect_docker' => false) do
        utilization_data = UtilizationData.new
        assert_nil utilization_data.to_collector_hash[:vendors]
      end
    end

    def test_docker_information_is_included_when_available
      NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns("47cbd16b77c50cbf71401")

      utilization_data = UtilizationData.new

      expected = {
        :docker => {
          :id => "47cbd16b77c50cbf71401"
        }
      }

      assert_equal expected, utilization_data.to_collector_hash[:vendors]
    end

    def test_docker_information_is_omitted_when_available_but_disabled_by_config
      NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns("47cbd16b77c50cbf71401")
      with_config(:'utilization.detect_docker' => false) do
        utilization_data = UtilizationData.new
        assert_nil utilization_data.to_collector_hash[:vendors]
      end
    end

    def test_logged_when_docker_container_id_is_unrecognized
      NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
      NewRelic::Agent::SystemInfo.stubs(:ram_in_mib).returns(128)
      NewRelic::Agent::SystemInfo.stubs(:proc_try_read).returns('whatever')
      NewRelic::Agent::SystemInfo.stubs(:parse_cgroup_ids).returns('cpu' => "*****YOLO*******")

      expects_logging(:debug, includes("YOLO"))
      utilization_data = UtilizationData.new
      assert_nil utilization_data.to_collector_hash[:vendors]
    end

    def test_aws_and_docker_information_is_included_when_both_available
      stub_aws_info(
        :instance_id => "i-e7e85ce1",
        :instance_type => "m3.medium",
        :availability_zone => "us-west-2b"
      )

      NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns("47cbd16b77c50cbf71401")

      utilization_data = UtilizationData.new

      expected = {
        :aws => {
          :id => "i-e7e85ce1",
          :type => "m3.medium",
          :zone => "us-west-2b"
        },
        :docker => {
          :id => "47cbd16b77c50cbf71401"
        }
      }

       assert_equal expected, utilization_data.to_collector_hash[:vendors]
    end

    def test_vendor_information_is_omitted_if_unavailable
      NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns(nil)

      utilization_data = UtilizationData.new

      assert_nil utilization_data.to_collector_hash[:vendors]
    end

    def test_hostname_is_present_in_collector_hash
      NewRelic::Agent::Hostname.stubs(:get).returns("host")

      utilization_data = UtilizationData.new

      assert_equal "host", utilization_data.to_collector_hash[:hostname]
    end

    def test_cpu_count_is_present_in_collector_hash
      NewRelic::Agent::SystemInfo.stubs(:num_logical_processors).returns(5)

      utilization_data = UtilizationData.new

      assert_equal 5, utilization_data.to_collector_hash[:logical_processors]
    end

    def test_memory_is_present_in_collector_hash
      NewRelic::Agent::SystemInfo.stubs(:ram_in_mib).returns(128)

      utilization_data = UtilizationData.new

      assert_equal 128, utilization_data.to_collector_hash[:total_ram_mib]
    end

    def test_memory_is_nil_when_proc_meminfo_is_unreadable
      NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("linux")
      NewRelic::Agent::SystemInfo.stubs(:proc_try_read).returns(nil)

      utilization_data = UtilizationData.new

      assert_nil utilization_data.to_collector_hash[:total_ram_mib], "Expected total_ram_mib to be nil"
    end

    def test_metadata_version_is_present_in_collector_hash
      utilization_data = UtilizationData.new

      assert_equal UtilizationData::METADATA_VERSION, utilization_data.to_collector_hash[:metadata_version]
    end

    def stub_aws_info(responses = {})
      AWSInfo.any_instance.stubs(:remote_fetch).with("instance-id").returns(responses[:instance_id])
      AWSInfo.any_instance.stubs(:remote_fetch).with("instance-type").returns(responses[:instance_type])
      AWSInfo.any_instance.stubs(:remote_fetch).with("placement/availability-zone").returns(responses[:availability_zone])
    end
  end
end
