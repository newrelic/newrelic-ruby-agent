# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/transaction_event_aggregator'

class NewRelic::Agent::TransactionEventAggregatorTest < Minitest::Test

  def setup
    freeze_time
    @event_listener = NewRelic::Agent::EventListener.new
    @sampler = NewRelic::Agent::TransactionEventAggregator.new(@event_listener)
  end

  # Helpers for DataContainerTests

  def create_container
    @sampler
  end

  def populate_container(sampler, n)
    n.times do |i|
      generate_request("whatever#{i}")
    end
  end

  include NewRelic::DataContainerTests

  # Tests

  def test_samples_on_transaction_finished_event
    with_sampler_config do
      generate_request
      assert_equal 1, @sampler.samples.length
    end
  end

  EVENT_DATA_INDEX = 0
  CUSTOM_ATTRIBUTES_INDEX = 1

  def test_custom_parameters_in_event_are_normalized_to_string_keys
    with_sampler_config do
      generate_request('whatever', :custom_params => {:bing => 2, 1 => 3})
      custom_attrs = single_sample[CUSTOM_ATTRIBUTES_INDEX]
      assert_equal 2, custom_attrs['bing']
      assert_equal 3, custom_attrs['1']
    end
  end

  def test_includes_custom_parameters_in_event
    with_sampler_config do
      generate_request('whatever', :custom_params => {'bing' => 2})
      custom_attrs = single_sample[CUSTOM_ATTRIBUTES_INDEX]
      assert_equal 2, custom_attrs['bing']
    end
  end

  def test_doesnt_include_custom_parameters_in_event_when_configured_not_to
    with_sampler_config('analytics_events.capture_attributes' => false) do
      generate_request('whatever', :custom_params => {'bing' => 2})
      custom_attrs = single_sample[CUSTOM_ATTRIBUTES_INDEX]
      assert_equal nil, custom_attrs['bing']
    end
  end

  def test_custom_parameters_in_event_cant_override_reserved_attributes
    with_sampler_config do
      metrics = NewRelic::Agent::TransactionMetrics.new()
      metrics.record_unscoped('HttpDispatcher', 0.01)

      generate_request('whatever',
        :metrics       => metrics,
        :custom_params => {'type' => 'giraffe', 'duration' => 'hippo'}
      )
      txn_event = single_sample[EVENT_DATA_INDEX]
      assert_equal 'Transaction', txn_event['type']
      assert_equal 0.1, txn_event['duration']

      custom_attrs = single_sample[CUSTOM_ATTRIBUTES_INDEX]
      assert_equal 'giraffe', custom_attrs['type']
      assert_equal 'hippo', custom_attrs['duration']
    end
  end

  def test_samples_on_transaction_finished_event_includes_expected_web_metrics
    txn_metrics = NewRelic::Agent::TransactionMetrics.new
    txn_metrics.record_unscoped('WebFrontend/QueueTime', 13)
    txn_metrics.record_unscoped('External/allWeb',       14)
    txn_metrics.record_unscoped('Datastore/all',         15)
    txn_metrics.record_unscoped("GC/Transaction/all",    16)

    with_sampler_config do
      generate_request('name', :metrics => txn_metrics)
      event_data = single_sample[EVENT_DATA_INDEX]
      assert_equal 13, event_data["queueDuration"]
      assert_equal 14, event_data["externalDuration"]
      assert_equal 15, event_data["databaseDuration"]
      assert_equal 16, event_data["gcCumulative"]

      assert_equal 1, event_data["externalCallCount"]
      assert_equal 1, event_data["databaseCallCount"]
    end
  end

  def test_samples_on_transaction_finished_includes_expected_background_metrics
    txn_metrics = NewRelic::Agent::TransactionMetrics.new
    txn_metrics.record_unscoped('External/allOther',  12)
    txn_metrics.record_unscoped('Datastore/all',      13)
    txn_metrics.record_unscoped("GC/Transaction/all", 14)

    with_sampler_config do
      generate_request('name', :metrics => txn_metrics)

      event_data = single_sample[EVENT_DATA_INDEX]
      assert_equal 12, event_data["externalDuration"]
      assert_equal 13, event_data["databaseDuration"]
      assert_equal 14, event_data["gcCumulative"]

      assert_equal 1, event_data["databaseCallCount"]
      assert_equal 1, event_data["externalCallCount"]
    end
  end

  def test_samples_on_transaction_finished_event_include_apdex_perf_zone
    with_sampler_config do
      generate_request('name', :apdex_perf_zone => 'S')

      event_data = single_sample[EVENT_DATA_INDEX]
      assert_equal 'S', event_data['nr.apdexPerfZone']
    end
  end

  def test_samples_on_transaction_finished_event_includes_guid
    with_sampler_config do
      generate_request('name', :guid => "GUID")
      assert_equal "GUID", single_sample[EVENT_DATA_INDEX]["nr.guid"]
    end
  end

  def test_samples_on_transaction_finished_event_includes_referring_transaction_guid
    with_sampler_config do
      generate_request('name', :referring_transaction_guid=> "REFER")
      assert_equal "REFER", single_sample[EVENT_DATA_INDEX]["nr.referringTransactionGuid"]
    end
  end

  def test_records_background_tasks
    with_sampler_config do
      generate_request('a', :type => :controller)
      generate_request('b', :type => :background)
      assert_equal 2, @sampler.samples.size
    end
  end

  def test_can_disable_sampling_for_analytics
    with_sampler_config( :'analytics_events.enabled' => false ) do
      generate_request
      assert @sampler.samples.empty?
    end
  end

  def test_harvest_returns_previous_sample_list
    with_sampler_config do
      5.times { generate_request }

      old_samples = @sampler.harvest!

      assert_equal 5, old_samples.size
      assert_equal 0, @sampler.samples.size
    end
  end

  def test_merge_merges_samples_back_into_buffer
    with_sampler_config do
      5.times { generate_request }
      old_samples = @sampler.harvest!
      5.times { generate_request }

      @sampler.merge!(old_samples)
      assert_equal(10, @sampler.samples.size)
    end
  end

  def test_merge_abides_by_max_samples_limit
    with_sampler_config(:'analytics_events.max_samples_stored' => 5) do
      4.times { generate_request }
      old_samples = @sampler.harvest!
      4.times { generate_request }

      @sampler.merge!(old_samples)
      assert_equal(5, @sampler.samples.size)
    end
  end

  def test_limits_total_number_of_samples_to_max_samples_stored
    with_sampler_config( :'analytics_events.max_samples_stored' => 100 ) do
      150.times { generate_request }
      assert_equal 100, @sampler.samples.size
    end
  end

  def test_resets_limits_on_harvest
    with_sampler_config( :'analytics_events.max_samples_stored' => 100 ) do
      50.times { generate_request('before') }
      samples_before = @sampler.samples
      assert_equal 50, samples_before.size

      @sampler.harvest!

      150.times { generate_request('after') }
      samples_after = @sampler.samples
      assert_equal 100, samples_after.size

      assert_equal 0, (samples_before & samples_after).size
    end
  end

  def test_does_not_drop_samples_when_used_from_multiple_threads
    with_sampler_config( :'analytics_events.max_samples_stored' => 100 * 100 ) do
      threads = []
      25.times do
        threads << Thread.new do
          100.times { generate_request }
        end
      end
      threads.each { |t| t.join }

      assert_equal(25 * 100, @sampler.samples.size)
    end
  end

  def test_includes_http_response_code_in_events
    generate_request('whatever', :http_response_code => 404)
    sample = single_sample
    code = sample[EVENT_DATA_INDEX]['httpResponseCode']
    assert_equal('404', code)
  end

  def test_synthetics_aggregation_limits
    with_sampler_config(:'synthetics.events_limit' => 10,
                        :'analytics_events.max_samples_stored' => 0) do
      20.times do
        generate_request('synthetic', :synthetics_resource_id => 100)
      end

      assert_equal 10, @sampler.samples.size
    end
  end

  def test_synthetics_events_overflow_to_transaction_buffer
    with_sampler_config(:'synthetics.events_limit' => 10) do
      20.times do
        generate_request('synthetic', :synthetics_resource_id => 100)
      end

      assert_equal 20, @sampler.samples.size
    end
  end

  def test_synthetics_events_kept_by_timestamp
    with_sampler_config(:'synthetics.events_limit' => 10,
                        :'analytics_events.max_samples_stored' => 0) do
      10.times do |i|
        generate_request('synthetic', :timestamp => i + 10, :synthetics_resource_id => 100)
      end

      generate_request('synthetic', :timestamp => 1, :synthetics_resource_id => 100)

      assert_equal 10, @sampler.samples.size
      timestamps = @sampler.samples.map do |(main, _)|
        main["timestamp"]
      end.sort

      assert_equal ([1] + (10..18).to_a), timestamps
    end
  end

  def test_synthetics_events_timestamp_bumps_go_to_main_buffer
    with_sampler_config(:'synthetics.events_limit' => 10) do
      10.times do |i|
        generate_request('synthetic', :timestamp => i + 10, :synthetics_resource_id => 100)
      end

      generate_request('synthetic', :timestamp => 1, :synthetics_resource_id => 100)

      assert_equal 11, @sampler.samples.size
    end
  end

  def test_merging_synthetics_still_applies_limit
    samples = with_sampler_config(:'synthetics.events_limit' => 20) do
      20.times do
        generate_request('synthetic', :synthetics_resource_id => 100)
      end
      @sampler.harvest!
    end

    with_sampler_config(:'synthetics.events_limit' => 10,
                        :'analytics_events.max_samples_stored' => 0) do
      @sampler.merge!(samples)
      assert_equal 10, @sampler.samples.size
    end
  end

  def test_synthetics_event_dropped_records_supportability_metrics
    with_sampler_config(:'synthetics.events_limit' => 20) do
      20.times do
        generate_request('synthetic', :synthetics_resource_id => 100)
      end

      @sampler.harvest!

      metric = 'Supportability/TransactionEventAggregator/synthetics_events_dropped'
      assert_metrics_not_recorded(metric)
    end
  end

  def test_synthetics_event_dropped_records_supportability_metrics
    with_sampler_config(:'synthetics.events_limit' => 10) do
      20.times do
        generate_request('synthetic', :synthetics_resource_id => 100)
      end

      @sampler.harvest!

      metric = 'Supportability/TransactionEventAggregator/synthetics_events_dropped'
      assert_metrics_recorded(metric => { :call_count => 10 })
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
      :custom_params => {}
    }.merge(options)
    @event_listener.notify(:transaction_finished, payload)
  end

  def with_sampler_config(options = {})
    defaults = { :'analytics_events.max_samples_stored' => 100 }
    defaults.merge!(options)
    with_config(defaults) do
      @event_listener.notify( :finished_configuring )
      yield
    end
  end

  def single_sample
    assert_equal 1, @sampler.samples.size
    @sampler.samples.first
  end

end
