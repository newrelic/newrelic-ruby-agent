# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/request_sampler'

class NewRelic::Agent::RequestSamplerTest < Test::Unit::TestCase

  def setup
    @event_listener = NewRelic::Agent::EventListener.new
    @sampler = NewRelic::Agent::RequestSampler.new( @event_listener )
  end

  def teardown
  end

  def test_samples_on_transaction_finished_event
    with_sampler_config( :'request_sampler.sample_rate_ms' => 0 ) do
      @event_listener.notify( :finished_configuring )
      @event_listener.notify( :transaction_finished, ['Controller/foo/bar'], 0.095 )

      assert_equal 1, @sampler.samples.length
    end
  end

  def test_samples_at_the_correct_rate
    with_sampler_config( :'request_sampler.sample_rate_ms' => 50 ) do
      @event_listener.notify( :finished_configuring )

      # (twice the sample rate over 6 seconds ~= 120 samples
      step_time( 6, 0.025 ) do |f|
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
      end

      assert_equal 119, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        delta = sample['timestamp'] - @sampler.samples[i-1]['timestamp']
        assert( "delta between samples should be >= 0.010" ) { delta >= 0.010 }
      end
    end
  end

  def test_downsamples_and_reduces_sample_rate_when_throttled
    with_sampler_config( :'request_sampler.sample_rate_ms' => 50 ) do
      @event_listener.notify( :finished_configuring )

      end_time = step_time( 6, 0.025 ) do |f|
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
      end

      @sampler.throttle( 2 )

      step_time( 6, 0.025, end_time ) do |f|
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
      end

      assert_equal 120, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        delta = sample['timestamp'] - @sampler.samples[i-1]['timestamp']
        assert( "delta between samples should be >= 0.020" ) { delta >= 0.020 }
      end
    end
  end

  def test_downsamples_and_reduces_sample_rate_when_throttled_multiple_times
    with_sampler_config( :'request_sampler.sample_rate_ms' => 50 ) do
      @event_listener.notify( :finished_configuring )
      start_time = current_time = Time.now

      end_time = step_time( 6, 0.025 ) do |f|
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
      end

      @sampler.throttle( 2 )

      end_time = step_time( 6, 0.025, end_time ) do |f|
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
      end

      @sampler.throttle( 3 )

      step_time( 6, 0.025, end_time ) do |f|
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
      end

      assert_equal 119, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        delta = sample['timestamp'] - @sampler.samples[i-1]['timestamp']
        assert( "delta between samples should be >= 0.030" ) { delta >= 0.030 }
      end
    end
  end

  def test_can_disable_sampling
    with_sampler_config( :'request_sampler.enabled' => false ) do
      @event_listener.notify( :finished_configuring )
      @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
      assert @sampler.samples.empty?
    end
  end

  def with_sampler_config(options = {})
    defaults =
    {
      :'request_sampler.enabled' => true,
      :'request_sampler.sample_rate_ms' => 50
    }

    defaults.merge!(options)
    with_config(defaults) do
      yield
    end
  end


  def assert_is_valid_transaction_sample( sample )
    assert_kind_of Hash, sample
    assert_equal 'Transaction', sample['type']
  end


  #
  # Helpers
  #

  def step_time( time_period, interval=0.05, start_time=Time.now )
    end_time = start_time + time_period

    freeze_time( start_time )
    while Time.now <= end_time
      yield
      advance_time( interval )
    end

    return end_time
  end

end
