# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/utilization_data'
require 'new_relic/agent/utilization/aws'

module NewRelic::Agent
  class UtilizationDataTest < Minitest::Test

    def setup
      stub_aws_info response_code: '404'
      stub_gcp_info response_code: '404'
      stub_azure_info response_code: '404'
    end

    def teardown
      NewRelic::Agent.drop_buffered_data
    end

    # ---

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

    def test_pcf_information_is_included_when_available
      utilization_data = UtilizationData.new

      with_pcf_env "CF_INSTANCE_GUID" => "ab326c0e-123e-47a1-65cc-45f6",
                   "CF_INSTANCE_IP"   => "101.1.149.48",
                   "MEMORY_LIMIT"     => "2048m" do

        expected = {
          :cf_instance_guid => "ab326c0e-123e-47a1-65cc-45f6",
          :cf_instance_ip => "101.1.149.48",
          :memory_limit   => "2048m"
        }

        assert_equal expected, utilization_data.to_collector_hash[:vendors][:pcf]
      end
    end

    def test_pcf_information_is_omitted_when_available_but_disabled_by_config
      with_config(:'utilization.detect_pcf' => false, :'utilization.detect_docker' => false) do
        utilization_data = UtilizationData.new
        with_pcf_env "CF_INSTANCE_GUID" => "ab326c0e-123e-47a1-65cc-45f6",
                     "CF_INSTANCE_IP"   => "101.1.149.48",
                     "MEMORY_LIMIT"     => "2048m" do

          assert_nil utilization_data.to_collector_hash[:vendors]
        end
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

    def test_ip_is_present_in_collector_hash
      NewRelic::Agent::SystemInfo.stubs(:ip_addresses).returns(['127.0.0.1'])

      utilization_data = UtilizationData.new

      assert_equal ['127.0.0.1'], utilization_data.to_collector_hash[:ip_address]
    end

    def test_full_hostname_is_present_in_collector_hash
      NewRelic::Agent::Hostname.stubs(:get_fqdn).returns("foobar.baz.com")

      utilization_data = UtilizationData.new

      assert_equal "foobar.baz.com", utilization_data.to_collector_hash[:full_hostname]
    end

    def test_full_hostname_omitted_if_empty_or_nil
      [nil, ""].each do |return_value|
        NewRelic::Agent::Hostname.stubs(:get_fqdn).returns(return_value)

        utilization_data = UtilizationData.new

        refute utilization_data.to_collector_hash.key?(:full_hostname)
      end
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

    # ---

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

    def with_pcf_env vars, &blk
      vars.each_pair { |k,v| ENV[k] = v }
      blk.call
      vars.keys.each { |k| ENV.delete k }
    end

    # ---

    load_cross_agent_test("utilization/utilization_json").each do |test_case|

      test_case = symbolize_keys_in_object test_case

      #temporary, until we implement utilization v5
      next if test_case[:testname].include? "kubernetes"
      test_case[:expected_output_json][:metadata_version] = 4

      define_method("test_#{test_case[:testname]}".tr(" ", "_")) do
        setup_cross_agent_test_stubs test_case

        # This is a little bit ugly, but TravisCI runs these tests in a docker environment,
        # which means we get an unexpected docker id in the vendors hash. Since none of the
        # cross agent tests expect docker ids in the vendors hash we can safely turn off
        # docker detection.
        options = convert_env_to_config_options(test_case).merge(:'utilization.detect_docker' => false)

        # additionally, boot_id will be picked up on linux/inside docker containers. so let's
        # add the local boot_id to the expected hash on linux.
        if RbConfig::CONFIG['host_os'] =~ /linux/
          refute test_case[:expected_output_json][:boot_id]
          test_case[:expected_output_json][:boot_id] = NewRelic::Agent::SystemInfo.proc_try_read('/proc/sys/kernel/random/boot_id').chomp
        end

        with_config options do
          test = ->{ assert_equal test_case[:expected_output_json], UtilizationData.new.to_collector_hash }
          if PCF_INPUTS.keys.all? {|k| test_case.key? k}
            with_pcf_env stub_pcf_env(test_case), &test
          else
            test[]
          end
        end
      end
    end

    def setup_cross_agent_test_stubs test_case
      stub_utilization_inputs test_case
      stub_aws_inputs test_case
      stub_azure_inputs(test_case)
      stub_gcp_inputs(test_case)
    end

    UTILIZATION_INPUTS = {
      :input_total_ram_mib => :ram_in_mib,
      :input_logical_processors => :cpu_count,
      :input_hostname => :hostname,
      :input_ip_address => :ip_addresses,
      :input_full_hostname => :fqdn
    }

    def stub_utilization_inputs test_case
      test_case.keys.each do |key|
        if meth = UTILIZATION_INPUTS[key]
          UtilizationData.any_instance.stubs(meth).returns(test_case[key])
        end
      end
    end

    AWS_INPUTS = {
      input_aws_id:   :instanceId,
      input_aws_type: :instanceType,
      input_aws_zone: :availabilityZone
    }

    def stub_aws_inputs test_case
      resp = test_case.reduce({}) {|h,(k,v)| h[AWS_INPUTS[k]] = v if AWS_INPUTS[k]; h}
      stub_aws_info response_body: JSON.dump(resp) unless resp.empty?
    end

    ENV_TO_OPTIONS = {
      :NEW_RELIC_UTILIZATION_LOGICAL_PROCESSORS => :'utilization.logical_processors',
      :NEW_RELIC_UTILIZATION_TOTAL_RAM_MIB =>  :'utilization.total_ram_mib',
      :NEW_RELIC_UTILIZATION_BILLING_HOSTNAME => :'utilization.billing_hostname'
    }

    NUMERIC_ENV_OPTS = [:NEW_RELIC_UTILIZATION_LOGICAL_PROCESSORS, :NEW_RELIC_UTILIZATION_TOTAL_RAM_MIB]

    def convert_env_to_config_options test_case
      env_inputs = test_case.fetch :input_environment_variables, {}
      env_inputs.keys.inject({}) do |memo, k|
        memo[ENV_TO_OPTIONS[k]] = NUMERIC_ENV_OPTS.include?(k) ? env_inputs[k].to_i : env_inputs[k]
        memo
      end
    end

    AZURE_INPUTS = {
      input_azure_location: :location,
      input_azure_name:     :name,
      input_azure_id:       :vmId,
      input_azure_size:     :vmSize
    }

    def stub_azure_inputs test_case
      resp = test_case.reduce({}) {|h,(k,v)| h[AZURE_INPUTS[k]] = v if AZURE_INPUTS[k]; h}
      stub_azure_info response_body: JSON.dump(resp) unless resp.empty?
    end

    GCP_INPUTS = {
      input_gcp_id:   :id,
      input_gcp_type: :machineType,
      input_gcp_name: :name,
      input_gcp_zone: :zone,
    }

    def stub_gcp_inputs test_case
      resp = test_case.reduce({}) {|h,(k,v)| h[GCP_INPUTS[k]] = v if GCP_INPUTS[k]; h}
      stub_gcp_info response_body: JSON.dump(resp) unless resp.empty?
    end

    PCF_INPUTS = {
      input_pcf_guid:      'CF_INSTANCE_GUID',
      input_pcf_ip:        'CF_INSTANCE_IP',
      input_pcf_mem_limit: 'MEMORY_LIMIT'
    }

    def stub_pcf_env test_case
      PCF_INPUTS.reduce({}) {|h,(k,v)| h[v] = test_case[k]; h}
    end

  end
end
