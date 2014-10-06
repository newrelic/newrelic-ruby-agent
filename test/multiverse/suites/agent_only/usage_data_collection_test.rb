# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'
require 'multiverse_helpers'
require 'fake_instance_metadata_service'

class UsageDataCollectionTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_gathers_instance_metadata
    instance_type     = 'test.type'
    availability_zone = 'us-west-2b'

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2008-02-01/meta-data/instance-type', instance_type)
      service.set_response_for_path('/2008-02-01/meta-data/placement/availability-zone', availability_zone)

      trigger_usage_data_collection_and_submission
    end

    attrs = last_submitted_usage_data_event
    assert_equal(instance_type,     attrs['instanceType'])
    assert_equal(availability_zone, attrs['dataCenter'])
  end

  def test_omits_instance_metadata_if_contains_invalid_characters
    instance_type     = '<script>lol</script>'
    availability_zone = ';us-west-2b'

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2008-02-01/meta-data/instance-type', instance_type)
      service.set_response_for_path('/2008-02-01/meta-data/placement/availability-zone', availability_zone)

      trigger_usage_data_collection_and_submission
    end

    attrs = last_submitted_usage_data_event
    assert_nil(attrs['instanceType'])
    assert_nil(attrs['dataCenter'])
  end

  def test_omits_instance_metadata_if_too_long
    instance_type     = 'a' * 1024
    availability_zone = 'b' * 1024

    with_fake_metadata_service do |service|
      service.set_response_for_path('/2008-02-01/meta-data/instance-type', instance_type)
      service.set_response_for_path('/2008-02-01/meta-data/placement/availability-zone', availability_zone)

      trigger_usage_data_collection_and_submission
    end

    attrs = last_submitted_usage_data_event
    assert_nil(attrs['instanceType'])
    assert_nil(attrs['dataCenter'])
  end

  def test_gathers_cpu_metadata
    fake_processor_info = {
      :num_physical_packages  => 2,
      :num_physical_cores     => 4,
      :num_logical_processors => 8
    }
    NewRelic::Agent::SystemInfo.stubs(:get_processor_info).returns(fake_processor_info)

    trigger_usage_data_collection_and_submission

    attrs = last_submitted_usage_data_event

    assert_equal(fake_processor_info[:num_physical_cores],     attrs['physicalCores'])
    assert_equal(fake_processor_info[:num_logical_processors], attrs['logicalProcessors'])
  end

  def test_nil_values_are_not_reported
    fake_processor_info = {
      :num_physical_cores     => nil,
      :num_logical_processors => 8
    }
    NewRelic::Agent::SystemInfo.stubs(:get_processor_info).returns(fake_processor_info)

    trigger_usage_data_collection_and_submission

    attrs = last_submitted_usage_data_event

    refute_includes(attrs.keys, 'physicalCores')
    assert_equal(fake_processor_info[:num_logical_processors], attrs['logicalProcessors'])
  end

  def test_retries_upon_failure_to_submit_usage_data
    $collector.stub_exception('analytic_event_data', nil, 503).once

    trigger_usage_data_collection_and_submission
    first_event_attempt = last_submitted_usage_data_event

    $collector.reset

    trigger_usage_data_submission
    next_event_attempt = last_submitted_usage_data_event

    assert_equal(first_event_attempt, next_event_attempt)
  end

  def last_submitted_usage_data_event
    submissions = $collector.calls_for(:analytic_event_data)
    assert_equal(1, submissions.size)

    events = submissions.last.events
    assert_equal(1, events.size)

    event = events.last
    attributes = event[1]
    attributes
  end

  def trigger_usage_data_collection
    NewRelic::Agent.agent.record_usage_data
  end

  def trigger_usage_data_submission
    agent.send(:transmit_event_data)
  end

  def trigger_usage_data_collection_and_submission
    trigger_usage_data_collection
    trigger_usage_data_submission
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
