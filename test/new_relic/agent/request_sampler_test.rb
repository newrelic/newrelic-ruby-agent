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
    with_debug_logging do
      @event_listener.notify( :config_finished )
      @event_listener.notify( :metrics_recorded, ['Controller/foo/bar'], 0.095 )
      assert_equal 1, @sampler.samples.length
    end
  end

end
