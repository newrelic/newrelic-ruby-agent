# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class SamplerManager < Test::Unit::TestCase

  class DummySampler
    attr_reader :id
    def self.supported_on_this_platform?; true; end
    def poll; end
  end
  class DummySampler2 < DummySampler; end

  def setup
    @events  = NewRelic::Agent::EventListener.new
    @manager = NewRelic::Agent::SamplerManager.new(@events)
  end

  def test_add_sampler_adds_a_sampler_of_requested_class
    @manager.add_sampler(DummySampler)
    assert_equal(1, @manager.samplers.size)
    assert_equal(DummySampler, @manager.samplers.first.class)
  end

  def test_add_sampler_does_add_non_dups
    @manager.add_sampler(DummySampler)
    @manager.add_sampler(DummySampler2)
    assert_equal(2, @manager.samplers.size)
    assert_equal([DummySampler, DummySampler2], @manager.samplers.map { |s| s.class })
  end

  def test_add_sampler_does_not_add_dups
    @manager.add_sampler(DummySampler)
    @manager.add_sampler(DummySampler)
    assert_equal(1, @manager.samplers.size)
  end

  def test_add_sampler_omits_unsupported_samplers
    DummySampler.stubs(:supported_on_this_platform?).returns(false)
    @manager.add_sampler(DummySampler)
    assert_equal(0, @manager.samplers.size)
  end

  def test_add_sampler_swallows_exceptions_during_sampler_creation
    DummySampler.stubs(:new).raises(StandardError)
    assert_nothing_raised { @manager.add_sampler(DummySampler) }
    assert_equal(0, @manager.samplers.size)
  end

  def test_poll_samplers_polls_samplers
    @manager.add_sampler(DummySampler)
    @manager.add_sampler(DummySampler2)
    samplers = @manager.samplers
    samplers.each { |s| s.expects(:poll) }
    @manager.poll_samplers
  end

  def test_poll_samplers_removes_busted_samplers_and_keeps_happy_ones
    @manager.add_sampler(DummySampler)
    @manager.add_sampler(DummySampler2)
    good_sampler, bad_sampler = @manager.samplers
    bad_sampler.stubs(:poll).raises('boo')
    assert_nothing_raised { @manager.poll_samplers }
    assert_equal(1, @manager.samplers.size)
    assert_equal([good_sampler], @manager.samplers)
  end

  def test_polls_samplers_on_before_harvest_event
    @manager.expects(:poll_samplers)
    @events.notify(:before_harvest)
  end
end
