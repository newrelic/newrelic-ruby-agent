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
      "metadata_version" => 1,
      "logical_processors" => 5,
      "total_ram_mib" => 128,
      "vendors" => {
        "aws" => {
          "id" => "i-e7e85ce1",
          "type" => "m3.medium",
          "zone" => "us-west-2b"
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

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2008-02-01/meta-data/instance-id', expected["vendors"]["aws"]["id"])
      service.set_response_for_path('/2008-02-01/meta-data/instance-type', expected["vendors"]["aws"]["type"])
      service.set_response_for_path('/2008-02-01/meta-data/placement/availability-zone', expected["vendors"]["aws"]["zone"])

      # this will trigger the agent to connect and send utilization data
      setup_agent

      assert_equal expected, single_connect_posted.utilization
    end
  end

  def test_omits_sending_vendor_data_on_connect_when_not_available
     expected = {
      "hostname" => "host",
      "metadata_version" => 1,
      "logical_processors" => 5,
      "total_ram_mib" => 128
    }

    NewRelic::Agent::Hostname.stubs(:get).returns("host")
    NewRelic::Agent::SystemInfo.stubs(:num_logical_processors).returns(5)
    NewRelic::Agent::SystemInfo.stubs(:ram_in_mib).returns(128)
    NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns(nil)
    NewRelic::Agent::AWSInfo.any_instance.stubs(:loaded?).returns(false)

    # this will trigger the agent to connect and send utilization data
    setup_agent

    assert_equal expected, single_connect_posted.utilization
  end

  def test_utilization_data_not_sent_when_disabled
    with_config :disable_utilization => true do
      setup_agent
      assert_nil single_connect_posted.utilization, "Expected utilization data to be nil"
    end
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
        def get_with_patch(uri)
          if uri.host == '169.254.169.254'
            uri.host = 'localhost'
            uri.port = @dummy_port
          end
          get_without_patch(uri)
        end

        alias_method :get_without_patch, :get
        alias_method :get, :get_with_patch
      end
    end
  end

  def unredirect_link_local_address
    Net::HTTP.class_eval do
      class << self
        alias_method :get, :get_without_patch
        undef_method :get_with_patch
      end
    end
  end
end
