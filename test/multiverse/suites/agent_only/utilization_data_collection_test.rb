# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'
require 'fake_instance_metadata_service'

class UtilizationDataCollectionTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent do
    @config = NewRelic::Agent::Configuration::DottedHash.new({:collect_utilization => true }, true)
    NewRelic::Agent.config.add_config_for_testing(@config, true)
  end

  def after_teardown
    NewRelic::Agent.config.remove_config(@config)
  end

  def test_hostname
    NewRelic::Agent::Hostname.stubs(:get).returns("hostile")
    trigger_usage_data_collection_and_submission

    data = last_submitted_utilization_data
    assert_equal("hostile", data.hostname)
  end

  def test_gathers_instance_metadata
    instance_type = 'test.type'

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2008-02-01/meta-data/instance-type', instance_type)
      trigger_usage_data_collection_and_submission
    end

    data = last_submitted_utilization_data
    assert_equal(instance_type, data.instance_type)
  end

  def test_omits_instance_metadata_if_contains_invalid_characters
    instance_type = '<script>lol</script>'

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2008-02-01/meta-data/instance-type', instance_type)
      trigger_usage_data_collection_and_submission
    end

    data = last_submitted_utilization_data
    assert_nil(data.instance_type)
  end

  def test_omits_instance_metadata_if_too_long
    instance_type = 'a' * 1024

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2008-02-01/meta-data/instance-type', instance_type)
      trigger_usage_data_collection_and_submission
    end

    data = last_submitted_utilization_data
    assert_nil(data.instance_type)
  end

  def test_gathers_cpu_metadata
    fake_processor_info = { :num_logical_processors => 8 }
    NewRelic::Agent::SystemInfo.stubs(:get_processor_info).returns(fake_processor_info)

    trigger_usage_data_collection_and_submission

    data = last_submitted_utilization_data
    assert_equal(fake_processor_info[:num_logical_processors], data.cpu_count)
  end

  def test_nil_cpu_values_reported
    fake_processor_info = { :num_logical_processors => nil }
    NewRelic::Agent::SystemInfo.stubs(:get_processor_info).returns(fake_processor_info)

    trigger_usage_data_collection_and_submission

    data = last_submitted_utilization_data
    assert_nil(data.cpu_count)
  end

  def test_gathers_docker_container_id
    NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns("whale")

    trigger_usage_data_collection_and_submission

    data = last_submitted_utilization_data
    assert_equal "whale", data.container_id
  end

  def test_nil_docker_container_id
    NewRelic::Agent::SystemInfo.stubs(:docker_container_id).returns(nil)

    trigger_usage_data_collection_and_submission

    data = last_submitted_utilization_data
    assert_nil data.container_id
  end

  def test_retries_upon_failure_to_submit_usage_data
    $collector.stub_exception('utilization_data', nil, 503).once

    trigger_usage_data_collection_and_submission
    first_attempt = last_submitted_utilization_data

    $collector.reset

    trigger_usage_data_collection_and_submission
    next_attempt = last_submitted_utilization_data

    assert_equal(first_attempt, next_attempt)
  end

  def last_submitted_utilization_data
    submissions = $collector.calls_for(:utilization_data)
    assert_equal(1, submissions.size)

    data = submissions.last
    assert_equal(4, data.body.size)

    data
  end

  def trigger_usage_data_collection_and_submission
    agent.send(:transmit_utilization_data)
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
