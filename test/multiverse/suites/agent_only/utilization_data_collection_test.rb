# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'
require 'fake_instance_metadata_service'

class UtilizationDataCollectionTest < Minitest::Test
  include MultiverseHelpers

  def test_sends_all_utilization_data_on_connect
    expected = {
      "hostname" => "host",
      "metadata_version" => 3,
      "logical_processors" => 5,
      "total_ram_mib" => 128,
      "vendors" => {
        "aws" => {
          "instanceId" => "i-08987cdeff7489fa7",
          "instanceType" => "c4.2xlarge",
          "availabilityZone" => "us-west-2c"
        },
        "docker" => {
          "id"=>"47cbd16b77c50cbf71401"
        }
      }
    }

    NewRelic::Agent::Hostname.stubs(:get).returns("host")
    NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns("47cbd16b77c50cbf71401")
    NewRelic::Agent::SystemInfo.stubs(:num_logical_processors).returns(5)
    NewRelic::Agent::SystemInfo.stubs(:ram_in_mib).returns(128)
    NewRelic::Agent::SystemInfo.stubs(:boot_id).returns(nil)

    aws_fixture_path = File.expand_path('../../../../fixtures/utilization/aws', __FILE__)
    fixture = File.read File.join(aws_fixture_path, "valid.json")

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2016-09-02/dynamic/instance-identity/document', fixture)

      # this will trigger the agent to connect and send utilization data
      setup_agent

      assert_equal expected, single_connect_posted.utilization
    end
  end

  def test_omits_sending_vendor_data_on_connect_when_not_available
     expected = {
      "hostname" => "host",
      "metadata_version" => 3,
      "logical_processors" => 5,
      "total_ram_mib" => 128
    }

    NewRelic::Agent::Hostname.stubs(:get).returns("host")
    NewRelic::Agent::SystemInfo.stubs(:num_logical_processors).returns(5)
    NewRelic::Agent::SystemInfo.stubs(:ram_in_mib).returns(128)
    NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns(nil)
    NewRelic::Agent::SystemInfo.stubs(:boot_id).returns(nil)
    NewRelic::Agent::Utilization::AWS.any_instance.stubs(:detect).returns(false)
    NewRelic::Agent::Utilization::GCP.any_instance.stubs(:detect).returns(false)

    # this will trigger the agent to connect and send utilization data
    setup_agent

    assert_equal expected, single_connect_posted.utilization
  end

  def with_fake_metadata_service
    metadata_service = NewRelic::FakeInstanceMetadataService.new
    metadata_service.run

    redirect_link_local_address(metadata_service.port)

    yield metadata_service
  ensure
    metadata_service.stop if metadata_service
    unredirect_link_local_address
  end

  def redirect_link_local_address(port)
    Net::HTTP.class_exec(port) do |p|
      @dummy_port = p

      class << self
        def start_with_patch(address, port=nil, p_addr=nil, p_port=nil, p_user=nil, p_pass=nil, &block)
          if address == '169.254.169.254'
            address = 'localhost'
            port = @dummy_port
          end
          start_without_patch(address, port, p_addr, p_port, p_user, p_pass, &block)
        end

        alias_method :start_without_patch, :start
        alias_method :start, :start_with_patch
      end
    end
  end

  def unredirect_link_local_address
    Net::HTTP.class_eval do
      class << self
         alias_method :start, :start_without_patch
         undef_method :start_with_patch
      end
    end
  end
end
