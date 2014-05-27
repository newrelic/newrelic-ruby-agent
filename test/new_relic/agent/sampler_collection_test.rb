# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class SamplerCollectionTest < Minitest::Test

  class DummySampler < NewRelic::Agent::Sampler
    named :dummy
    def poll; end
  end

  class DummySampler2 < NewRelic::Agent::Sampler
    named :dummy2
    def poll; end
  end

  def setup
    @events     = NewRelic::Agent::EventListener.new
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

  def test_add_sampler_omits_disabled_samplers
    with_config(:disable_dummy_sampler => true) do
      @collection.add_sampler(DummySampler)
      assert_equal(0, @collection.to_a.size)
    end
  end

  def test_add_sampler_swallows_exceptions_during_sampler_creation
    DummySampler.stubs(:new).raises(StandardError)
    @collection.add_sampler(DummySampler)
    assert_equal(0, @collection.to_a.size)
  end

  def test_add_sampler_calls_setup_events_with_event_listener_if_present
    sampler = DummySampler.new
    DummySampler.stubs(:new).returns(sampler)
    sampler.expects(:setup_events).with(@events)
    @collection.add_sampler(DummySampler)
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
    @collection.poll_samplers
    assert_equal(1, @collection.to_a.size)
    assert_equal([good_sampler], @collection.to_a)
  end

  def test_polls_samplers_on_before_harvest_event
    @collection.expects(:poll_samplers)
    @events.notify(:before_harvest)
  end
end
