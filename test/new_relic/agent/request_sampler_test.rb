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
    with_config( :'request_sampler.sample_rate_ms' => 10 ) do
      @event_listener.notify( :finished_configuring )
      start_time = Time.now

      0.upto( 51 ) do |i|
        Time.stubs( :now ).returns( start_time + (i * 0.001) + 0.001 )
        @event_listener.notify( :metric_recorded, 'Controller/foo/bar', 0.025 * i )
      end

      assert_equal 5, @sampler.samples.length
      @sampler.samples.each do |sample|
        assert_is_valid_transaction_sample( sample )
      end
      @sampler.samples.each_with_index do |sample, i|
        next if i.zero?
        delta = sample['timestamp'] - @sampler.samples[i-1]['timestamp']
        assert( "delta between samples shoud be >= 0.010" ) { delta >= 0.010 }
      end
    end
  end

  def assert_is_valid_transaction_sample( sample )
    assert_kind_of Hash, sample
    assert_equal 'Transaction', sample['type']
  end

end
