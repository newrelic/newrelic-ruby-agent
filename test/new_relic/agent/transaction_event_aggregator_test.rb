# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/transaction_event_aggregator'
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/transaction_event'

class NewRelic::Agent::TransactionEventAggregatorTest < Minitest::Test

  def setup
    freeze_time
    @event_aggregator = NewRelic::Agent::TransactionEventAggregator.new

    @attributes = nil
  end

  # Helpers for DataContainerTests

  def create_container
    @event_aggregator
  end

  def populate_container(sampler, n)
    n.times do |i|
      generate_request("whatever#{i}")
    end
  end

  include NewRelic::DataContainerTests

  # Tests

  def test_samples_on_transaction_finished_event
    generate_request
    assert_equal 1, @event_aggregator.samples.length
  end

  EVENT_DATA_INDEX = 0
  CUSTOM_ATTRIBUTES_INDEX = 1
  AGENT_ATTRIBUTES_INDEX = 2

  def test_custom_attributes_in_event_are_normalized_to_string_keys
    attributes.merge_custom_attributes(:bing => 2, 1 => 3)
    generate_request('whatever')

    result = captured_transaction_event[CUSTOM_ATTRIBUTES_INDEX]
    assert_equal 2, result['bing']
    assert_equal 3, result['1']
  end

  def test_agent_attributes_in_event_are_normalized_to_string_keys
    attributes.add_agent_attribute(:yahoo, 7, NewRelic::Agent::AttributeFilter::DST_ALL)
    attributes.add_agent_attribute(4, 2, NewRelic::Agent::AttributeFilter::DST_ALL)
    generate_request('puce')

    result = captured_transaction_event[AGENT_ATTRIBUTES_INDEX]
    assert_equal 7, result[:yahoo]
    assert_equal 2, result[4]

  end

  def test_error_is_included_in_event_data
    generate_request('whatever', :error => true)

    event_data, *_ = captured_transaction_event

    assert event_data['error']
  end

  def test_includes_custom_attributes_in_event
    attributes.merge_custom_attributes('bing' => 2)
    generate_request('whatever')

    custom_attrs = captured_transaction_event[CUSTOM_ATTRIBUTES_INDEX]
    assert_equal 2, custom_attrs['bing']
  end

  def test_includes_agent_attributes_in_event
    attributes.add_agent_attribute('bing', 2, NewRelic::Agent::AttributeFilter::DST_ALL)
    generate_request('whatever')

    agent_attrs = captured_transaction_event[AGENT_ATTRIBUTES_INDEX]
    assert_equal 2, agent_attrs['bing']
  end

  def test_doesnt_include_custom_attributes_in_event_when_configured_not_to
    with_config('transaction_events.attributes.enabled' => false) do
      attributes.merge_custom_attributes('bing' => 2)
      generate_request('whatever')

      custom_attrs = captured_transaction_event[CUSTOM_ATTRIBUTES_INDEX]
      assert_empty custom_attrs
    end
  end

  def test_doesnt_include_agent_attributes_in_event_when_configured_not_to
    with_config('transaction_events.attributes.enabled' => false) do
      attributes.add_agent_attribute('bing', 2, NewRelic::Agent::AttributeFilter::DST_ALL)
      generate_request('whatever')

      agent_attrs = captured_transaction_event[AGENT_ATTRIBUTES_INDEX]
      assert_empty agent_attrs
    end
  end


  def test_doesnt_include_custom_attributes_in_event_when_configured_not_to_with_legacy_setting
    with_config('analytics_events.capture_attributes' => false) do
      attributes.merge_custom_attributes('bing' => 2)
      generate_request('whatever')

      custom_attrs = captured_transaction_event[CUSTOM_ATTRIBUTES_INDEX]
      assert_empty custom_attrs
    end
  end

  def test_doesnt_include_agent_attributes_in_event_when_configured_not_to_with_legacy_setting
    with_config('analytics_events.capture_attributes' => false) do
      attributes.add_agent_attribute('bing', 2, NewRelic::Agent::AttributeFilter::DST_ALL)
      generate_request('whatever')

      agent_attrs = captured_transaction_event[AGENT_ATTRIBUTES_INDEX]
      assert_empty agent_attrs
    end
  end

  def test_custom_attributes_in_event_cant_override_reserved_attributes
    metrics = NewRelic::Agent::TransactionMetrics.new()
    metrics.record_unscoped('HttpDispatcher', 0.01)

    attributes.merge_custom_attributes('type' => 'giraffe', 'duration' => 'hippo')
    generate_request('whatever', :metrics => metrics)

    txn_event = captured_transaction_event[EVENT_DATA_INDEX]
    assert_equal 'Transaction', txn_event['type']
    assert_equal 0.1, txn_event['duration']

    custom_attrs = captured_transaction_event[CUSTOM_ATTRIBUTES_INDEX]
    assert_equal 'giraffe', custom_attrs['type']
    assert_equal 'hippo', custom_attrs['duration']
  end

  def test_samples_on_transaction_finished_event_includes_expected_web_metrics
    txn_metrics = NewRelic::Agent::TransactionMetrics.new
    txn_metrics.record_unscoped('WebFrontend/QueueTime', 13)
    txn_metrics.record_unscoped('External/allWeb',       14)
    txn_metrics.record_unscoped('Datastore/all',         15)
    txn_metrics.record_unscoped("GC/Transaction/all",    16)


    generate_request('name', :metrics => txn_metrics)
    event_data = captured_transaction_event[EVENT_DATA_INDEX]
    assert_equal 13, event_data["queueDuration"]
    assert_equal 14, event_data["externalDuration"]
    assert_equal 15, event_data["databaseDuration"]
    assert_equal 16, event_data["gcCumulative"]

    assert_equal 1, event_data["externalCallCount"]
    assert_equal 1, event_data["databaseCallCount"]
  end

  def test_samples_on_transaction_finished_includes_expected_background_metrics
    txn_metrics = NewRelic::Agent::TransactionMetrics.new
    txn_metrics.record_unscoped('External/allOther',  12)
    txn_metrics.record_unscoped('Datastore/all',      13)
    txn_metrics.record_unscoped("GC/Transaction/all", 14)


    generate_request('name', :metrics => txn_metrics)

    event_data = captured_transaction_event[EVENT_DATA_INDEX]
    assert_equal 12, event_data["externalDuration"]
    assert_equal 13, event_data["databaseDuration"]
    assert_equal 14, event_data["gcCumulative"]

    assert_equal 1, event_data["databaseCallCount"]
    assert_equal 1, event_data["externalCallCount"]
  end

  def test_samples_on_transaction_finished_event_include_apdex_perf_zone
    generate_request('name', :apdex_perf_zone => 'S')

    event_data = captured_transaction_event[EVENT_DATA_INDEX]
    assert_equal 'S', event_data['nr.apdexPerfZone']
  end

  def test_samples_on_transaction_finished_event_includes_guid
    generate_request('name', :guid => "GUID")
    assert_equal "GUID", captured_transaction_event[EVENT_DATA_INDEX]["nr.guid"]
  end

  def test_samples_on_transaction_finished_event_includes_referring_transaction_guid
    generate_request('name', :referring_transaction_guid=> "REFER")
    assert_equal "REFER", captured_transaction_event[EVENT_DATA_INDEX]["nr.referringTransactionGuid"]
  end

  def test_records_background_tasks
    generate_request('a', :type => :controller)
    generate_request('b', :type => :background)
    assert_equal 2, @event_aggregator.samples.size
  end

  def test_can_disable_sampling_for_analytics
    with_config( :'analytics_events.enabled' => false ) do
      generate_request
      assert @event_aggregator.samples.empty?
    end
  end

  def test_harvest_returns_previous_sample_list
    5.times { generate_request }

    _, old_samples = @event_aggregator.harvest!

    assert_equal 5, old_samples.size
    assert_equal 0, @event_aggregator.samples.size
  end

  def test_merge_merges_samples_back_into_buffer
    5.times { generate_request }
    old_samples = @event_aggregator.harvest!
    5.times { generate_request }

    @event_aggregator.merge!(old_samples)
    assert_equal(10, @event_aggregator.samples.size)
  end

  def test_merge_abides_by_max_samples_limit
    with_config(:'analytics_events.max_samples_stored' => 5) do
      4.times { generate_request }
      old_samples = @event_aggregator.harvest!
      4.times { generate_request }

      @event_aggregator.merge!(old_samples)
      assert_equal(5, @event_aggregator.samples.size)
    end
  end

  def test_sample_counts_are_correct_after_merge
    with_config :'analytics_events.max_samples_stored' => 5 do
      buffer = @event_aggregator.instance_variable_get :@buffer

      4.times { generate_request }
      last_harvest = @event_aggregator.harvest!

      assert_equal 4, buffer.seen_lifetime
      assert_equal 4, buffer.captured_lifetime
      assert_equal 4, last_harvest[0][:events_seen]

      4.times { generate_request }
      @event_aggregator.merge! last_harvest

      reservoir_stats, samples = @event_aggregator.harvest!

      assert_equal 5, samples.size
      assert_equal 8, reservoir_stats[:events_seen]
      assert_equal 8, buffer.seen_lifetime
      assert_equal 5, buffer.captured_lifetime
    end
  end

  def test_limits_total_number_of_samples_to_max_samples_stored
    with_config( :'analytics_events.max_samples_stored' => 100 ) do
      150.times { generate_request }
      assert_equal 100, @event_aggregator.samples.size
    end
  end

  def test_resets_limits_on_harvest
    with_config( :'analytics_events.max_samples_stored' => 100 ) do
      50.times { generate_request('before') }
      samples_before = @event_aggregator.samples
      assert_equal 50, samples_before.size

      @event_aggregator.harvest!

      150.times { generate_request('after') }
      samples_after = @event_aggregator.samples
      assert_equal 100, samples_after.size

      assert_equal 0, (samples_before & samples_after).size
    end
  end

  def test_does_not_drop_samples_when_used_from_multiple_threads
    with_config( :'analytics_events.max_samples_stored' => 100 * 100 ) do
      threads = []
      25.times do
        threads << Thread.new do
          100.times { generate_request }
        end
      end
      threads.each { |t| t.join }

      assert_equal(25 * 100, @event_aggregator.samples.size)
    end
  end

  #
  # Helpers
  #

  def generate_request(name='whatever', options={})
    payload = {
      :name => "Controller/#{name}",
      :type => :controller,
      :start_timestamp => options[:timestamp] || Time.now.to_f,
      :duration => 0.1,
      :attributes => attributes,
      :error => false
    }.merge(options)

    @event_aggregator.append TransactionEvent.new(payload)
  end

  def captured_transaction_event
    assert_equal 1, @event_aggregator.samples.size
    @event_aggregator.samples.first
  end

  def attributes
    if @attributes.nil?
      filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
      @attributes = NewRelic::Agent::Transaction::Attributes.new(filter)
    end

    @attributes
  end
end
