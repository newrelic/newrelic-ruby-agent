# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class SamplerCollectionTest < Test::Unit::TestCase

  class DummySampler
    attr_reader :id
    def self.supported_on_this_platform?; true; end
    def poll; end
  end
  class DummySampler2 < DummySampler; end

  def setup
    @events  = NewRelic::Agent::EventListener.new
    @collection = NewRelic::Agent::SamplerCollection.new(@events)
  end

  def test_add_sampler_adds_a_sampler_of_requested_class
    @collection.add_sampler(DummySampler)
    assert_equal(1, @collection.to_a.size)
    assert_equal(DummySampler, @collection.to_a.first.class)
  end

  def test_add_sampler_does_add_non_dups
    @collection.add_sampler(DummySampler)
    @collection.add_sampler(DummySampler2)
    assert_equal(2, @collection.to_a.size)
    assert_equal([DummySampler, DummySampler2], @collection.map { |s| s.class })
  end

  def test_add_sampler_does_not_add_dups
    @collection.add_sampler(DummySampler)
    @collection.add_sampler(DummySampler)
    assert_equal(1, @collection.to_a.size)
  end

  def test_add_sampler_omits_unsupported_samplers
    DummySampler.stubs(:supported_on_this_platform?).returns(false)
    @collection.add_sampler(DummySampler)
    assert_equal(0, @collection.to_a.size)
  end

  def test_add_sampler_swallows_exceptions_during_sampler_creation
    DummySampler.stubs(:new).raises(StandardError)
    assert_nothing_raised { @collection.add_sampler(DummySampler) }
    assert_equal(0, @collection.to_a.size)
  end

  def test_poll_samplers_polls_samplers
    @collection.add_sampler(DummySampler)
    @collection.add_sampler(DummySampler2)
    @collection.each { |s| s.expects(:poll) }
    @collection.poll_samplers
  end

  def test_poll_samplers_removes_busted_samplers_and_keeps_happy_ones
    @collection.add_sampler(DummySampler)
    @collection.add_sampler(DummySampler2)
    good_sampler, bad_sampler = @collection.to_a
    bad_sampler.stubs(:poll).raises('boo')
    assert_nothing_raised { @collection.poll_samplers }
    assert_equal(1, @collection.to_a.size)
    assert_equal([good_sampler], @collection.to_a)
  end

  def test_polls_samplers_on_before_harvest_event
    @collection.expects(:poll_samplers)
    @events.notify(:before_harvest)
  end
end
