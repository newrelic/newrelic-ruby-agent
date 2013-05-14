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

  def test_samples_on_metrics_recorded_events
    with_config( :'request_sampler.sample_rate_ms' => 0 ) do
      @event_listener.notify( :finished_configuring )
      @event_listener.notify( :metric_recorded, ['Controller/foo/bar'], 0.095 )

      assert_equal 1, @sampler.samples.length
    end
  end

  def test_samples_at_the_correct_rate
    with_config( :'request_sampler.sample_rate_ms' => 50 ) do
      @event_listener.notify( :finished_configuring )

      step_time( 2, 0.02 ) do |f|
        @event_listener.notify( :metric_recorded, 'Controller/foo/bar', 0.200 )
      end

      assert_equal 33, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        delta = sample.first['timestamp'] - @sampler.samples[i-1][0]['timestamp']
        assert( "delta between samples should be >= 0.010" ) { delta >= 0.010 }
      end
    end
  end

  def test_downsamples_and_reduces_sample_rate_when_throttled
    with_config( :'request_sampler.sample_rate_ms' => 50 ) do
      @event_listener.notify( :finished_configuring )

      end_time = step_time( 2, 0.02 ) do |f|
        @event_listener.notify( :metric_recorded, 'Controller/foo/bar', 0.200 )
      end

      @sampler.throttle( 2 )

      step_time( 2, 0.02, end_time ) do |f|
        @event_listener.notify( :metric_recorded, 'Controller/foo/bar', 0.200 )
      end

      assert_equal 35, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        delta = sample.first['timestamp'] - @sampler.samples[i-1][0]['timestamp']
        assert( "delta between samples should be >= 0.020" ) { delta >= 0.020 }
      end
    end
  end

  def test_downsamples_and_reduces_sample_rate_when_throttled_multiple_times
    with_config( :'request_sampler.sample_rate_ms' => 50 ) do
      @event_listener.notify( :finished_configuring )
      start_time = current_time = Time.now

      end_time = step_time( 2, 0.02 ) do |f|
        @event_listener.notify( :metric_recorded, 'Controller/foo/bar', 0.200 )
      end

      @sampler.throttle( 2 )

      end_time = step_time( 2, 0.02, end_time ) do |f|
        @event_listener.notify( :metric_recorded, 'Controller/foo/bar', 0.200 )
      end

      @sampler.throttle( 3 )

      step_time( 2, 0.02, end_time ) do |f|
        @event_listener.notify( :metric_recorded, 'Controller/foo/bar', 0.200 )
      end

      assert_equal 24, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        delta = sample.first['timestamp'] - @sampler.samples[i-1][0]['timestamp']
        assert( "delta between samples should be >= 0.030" ) { delta >= 0.030 }
      end
    end
  end

  def assert_is_valid_transaction_sample( sample )
    assert_kind_of Array, sample
    assert_equal 1, sample.length

    inner_sample = sample[0]
    assert_kind_of Hash, inner_sample
    assert_equal 'Transaction', inner_sample['type']
  end


  #
  # Helpers
  #

  def step_time( time_period, interval=0.05, start_time=Time.now )
    end_time   = start_time + time_period

    start_time.to_f.step( end_time.to_f, interval ) do |f|
      Time.stubs( :now ).returns( Time.at(f) )
      yield( f )
    end

    return end_time
  end

end
