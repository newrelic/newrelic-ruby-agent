# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/utilization_data'
require 'new_relic/agent/utilization/aws'

module NewRelic::Agent
  class UtilizationDataTest < Minitest::Test

    # recurses through hashes and arrays and symbolizes keys
    def self.symbolize_keys_in_object(object)
      case object
      when Hash
        object.inject({}) do |memo, (k, v)|
          memo[k.to_sym] = symbolize_keys_in_object(v)
          memo
        end
      when Array
        object.map {|o| symbolize_keys_in_object(o)}
      else
        object
      end
    end

    def setup
      stub_aws_info response_code: '404'
      stub_gcp_info response_code: '404'
      stub_azure_info response_code: '404'
    end

    def teardown
      NewRelic::Agent.drop_buffered_data
    end

    def test_aws_information_is_included_when_available
      stub_aws_info
      utilization_data = UtilizationData.new

      expected = {
        :instanceId => "i-08987cdeff7489fa7",
        :instanceType => "c4.2xlarge",
        :availabilityZone => "us-west-2c"
      }

      assert_equal expected, utilization_data.to_collector_hash[:vendors][:aws]
    end

    def test_aws_information_is_omitted_when_available_but_disabled_by_config
      stub_aws_info

      with_config(:'utilization.detect_aws' => false, :'utilization.detect_docker' => false) do
        utilization_data = UtilizationData.new
        assert_nil utilization_data.to_collector_hash[:vendors]
      end
    end

    def test_azure_information_is_included_when_available
      stub_azure_info
      utilization_data = UtilizationData.new

      expected = {
        :vmId     => "c84ffaa7-1b0a-4aa6-9f5c-0912655d9870",
        :name     => "rubytest",
        :vmSize   => "Standard_DS1_v2",
        :location => "eastus"
      }

      assert_equal expected, utilization_data.to_collector_hash[:vendors][:azure]
    end

    def test_azure_information_is_omitted_when_available_but_disabled_by_config
      stub_azure_info

      with_config(:'utilization.detect_azure' => false, :'utilization.detect_docker' => false) do
        utilization_data = UtilizationData.new
        assert_nil utilization_data.to_collector_hash[:vendors]
      end
    end

    def test_gcp_information_is_included_when_available
      stub_gcp_info
      utilization_data = UtilizationData.new

      expected = {
        :id => "4332984205593314925",
        :machineType => "custom-1-1024",
        :name => "aef-default-20170714t143150-1q67",
        :zone => "us-central1-b"
      }

      assert_equal expected, utilization_data.to_collector_hash[:vendors][:gcp]
    end

    def test_gcp_information_is_omitted_when_available_but_disabled_by_config
      stub_gcp_info

      with_config(:'utilization.detect_gcp' => false, :'utilization.detect_docker' => false) do
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
      stub_aws_info

      NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns("47cbd16b77c50cbf71401")
      utilization_data = UtilizationData.new

      expected = {
        :aws => {
          :instanceId => "i-08987cdeff7489fa7",
          :instanceType => "c4.2xlarge",
          :availabilityZone => "us-west-2c"
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

    def test_configured_hostname_added_to_config_hash
      with_config(:'utilization.billing_hostname' => 'BillNye') do
        utilization_data = UtilizationData.new
        assert_equal 'BillNye', utilization_data.to_collector_hash[:config][:hostname]
      end
    end

    def test_configured_logical_processors_added_to_config_hash
      with_config(:'utilization.logical_processors' => 42) do
        utilization_data = UtilizationData.new
        assert_equal 42, utilization_data.to_collector_hash[:config][:logical_processors]
      end
    end

    def test_configured_total_ram_mib_added_to_config_hash
      with_config(:'utilization.total_ram_mib' => 42) do
        utilization_data = UtilizationData.new
        assert_equal 42, utilization_data.to_collector_hash[:config][:total_ram_mib]
      end
    end

    def test_boot_id_is_present_in_collector_hash
      NewRelic::Agent::SystemInfo.stubs(:boot_id).returns("boot-id")

      utilization_data = UtilizationData.new

      assert_equal "boot-id", utilization_data.to_collector_hash[:boot_id]
    end

    def stub_aws_info response_code: '200', response_body: default_aws_response
      stubbed_response = stub(code: response_code, body: response_body)
      Utilization::AWS.any_instance.stubs(:request_metadata).returns(stubbed_response)
    end

    def default_aws_response
      aws_fixture_path = File.expand_path('../../../fixtures/utilization/aws', __FILE__)
      File.read File.join(aws_fixture_path, "valid.json")
    end

    def stub_azure_info response_code: '200', response_body: default_azure_response
      stubbed_response = stub(code: response_code, body: response_body)
      Utilization::Azure.any_instance.stubs(:request_metadata).returns(stubbed_response)
    end

    def default_azure_response
      azure_fixture_path = File.expand_path('../../../fixtures/utilization/azure', __FILE__)
      File.read File.join(azure_fixture_path, 'valid.json')
    end

    def stub_gcp_info response_code: '200', response_body: default_gcp_response
      stubbed_response = stub(code: response_code, body: response_body)
      Utilization::GCP.any_instance.stubs(:request_metadata).returns(stubbed_response)
    end

    def default_gcp_response
      aws_fixture_path = File.expand_path('../../../fixtures/utilization/gcp', __FILE__)
      File.read File.join(aws_fixture_path, "valid.json")
    end
  end
end
