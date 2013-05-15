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

  def test_samples_on_transaction_finished_events
    with_config( :'request_sampler.enabled' => true ) do
      freeze_time
      @event_listener.notify( :finished_configuring )
      advance_time( 0.60 )
      @event_listener.notify( :transaction_finished, ['Controller/foo/bar'], 0.095 )

      assert_equal 1, @sampler.samples.length
    end
  end

  def test_samples_at_the_correct_rate
    with_config( :'request_sampler.enabled' => true ) do
      freeze_time
      @event_listener.notify( :finished_configuring )

      # 240 requests over 6 seconds => 120 samples
      # with_debug_logging do
      241.times do
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
        advance_time( 0.025 )
      end
      # end

      assert_equal 120, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        seconds = sample['timestamp'] - @sampler.samples[i-1]['timestamp']
        assert_in_delta( seconds, 0.050, 0.001 )
      end
    end
  end

  def test_downsamples_and_reduces_sample_rate_when_throttled
    with_config( :'request_sampler.enabled' => true ) do
      freeze_time
      @event_listener.notify( :finished_configuring )

      240.times do
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
        advance_time( 0.025 )
      end

      @sampler.throttle( 2 )

      241.times do
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
        advance_time( 0.025 )
      end

      assert_equal 120, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        seconds = sample['timestamp'] - @sampler.samples[i-1]['timestamp']
        assert_in_delta( seconds, 0.100, 0.026 )
      end
    end
  end

  def test_downsamples_and_reduces_sample_rate_when_throttled_multiple_times
    with_config( :'request_sampler.enabled' => true ) do
      freeze_time
      @event_listener.notify( :finished_configuring )

      240.times do
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
        advance_time( 0.025 )
      end

      @sampler.throttle( 2 )

      240.times do
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
        advance_time( 0.025 )
      end

      @sampler.throttle( 3 )

      241.times do
        @event_listener.notify( :transaction_finished, 'Controller/foo/bar', 0.200 )
        advance_time( 0.025 )
      end

      assert_equal 120, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        seconds = sample['timestamp'] - @sampler.samples[i-1]['timestamp']
        assert_in_delta( seconds, 0.150, 0.051 )
      end
    end
  end


  def test_allows_sample_rates_as_frequent_as_25ms
    with_config( :'request_sampler.sample_rate_ms' => 25 ) do
      @event_listener.notify( :finished_configuring )
      assert_equal 25, @sampler.normal_sample_rate_ms
    end
  end

  def test_resets_sample_rates_more_frequent_than_25ms_to_25ms
    with_config( :'request_sampler.sample_rate_ms' => 1 ) do
      @event_listener.notify( :finished_configuring )
      assert_equal 25, @sampler.normal_sample_rate_ms
    end
  end


  #
  # Helpers
  #

  def assert_is_valid_transaction_sample( sample )
    assert_kind_of Hash, sample
    assert_equal 'Transaction', sample['type']
  end

end
