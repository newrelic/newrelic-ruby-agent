# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/request_sampler'

class NewRelic::Agent::RequestSamplerTest < Test::Unit::TestCase

  def setup
    freeze_time
    @event_listener = NewRelic::Agent::EventListener.new
    @sampler = NewRelic::Agent::RequestSampler.new( @event_listener )
  end

  def test_samples_on_transaction_finished_event
    with_sampler_config do
      generate_request
      assert_equal 1, @sampler.samples.length
    end
  end

  def test_samples_on_transaction_finished_event_includes_overview_metrics
    with_sampler_config do
      generate_request('name', :overview_metrics => {:foo => :bar})
      assert_equal :bar, @sampler.samples.first[:foo]
    end
  end

  def test_can_disable_sampling_for_analytics
    with_sampler_config( :'analytics_events.enabled' => false ) do
      generate_request
      assert @sampler.samples.empty?
    end
  end

  def test_can_disable_sampling_for_analytics_transactions
    with_sampler_config( :'analytics_events.transactions.enabled' => false ) do
      generate_request
      assert @sampler.samples.empty?
    end
  end

  def test_harvest_returns_previous_sample_list
    with_sampler_config do
      5.times { generate_request }

      old_samples = @sampler.harvest

      assert_equal 5, old_samples.size
      assert_equal 0, @sampler.samples.size
    end
  end

  def test_merge_merges_samples_back_into_buffer
    with_sampler_config do
      5.times { generate_request }
      old_samples = @sampler.harvest
      5.times { generate_request }

      @sampler.merge!(old_samples)
      assert_equal(10, @sampler.samples.size)
    end
  end

  def test_merge_abides_by_max_samples_limit
    with_sampler_config(:'analytics_events.max_samples_stored' => 5) do
      4.times { generate_request }
      old_samples = @sampler.harvest
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
    with_sampler_config( :'request_sampler.max_samples_stored' => 100 ) do
      50.times { generate_request('before') }
      samples_before = @sampler.samples
      assert_equal 50, samples_before.size

      @sampler.harvest

      150.times { generate_request('after') }
      samples_after = @sampler.samples
      assert_equal 100, samples_after.size

      assert_equal 0, (samples_before & samples_after).size
    end
  end

  def test_does_not_record_requests_from_background_tasks
    with_sampler_config do
      generate_request('a', :type => :controller)
      generate_request('b', :type => :background)
      assert_equal 1, @sampler.samples.size
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

  #
  # Helpers
  #

  def generate_request(name='whatever', options={})
    payload = {
      :name => "Controller/#{name}",
      :type => :controller,
      :start_timestamp => Time.now.to_f,
      :duration => 0.1,
      :overview_metrics => {}
    }.merge(options)
    @event_listener.notify(:transaction_finished, payload)
  end

  def with_sampler_config(options = {})
    defaults =
    {
      :'analytics_events.max_samples_stored' => 100
    }

    defaults.merge!(options)
    with_config(defaults) do
      @event_listener.notify( :finished_configuring )
      yield
    end
  end

  def assert_is_valid_transaction_sample( sample )
    assert_kind_of Hash, sample
    assert_equal 'Transaction', sample['type']
  end

end
