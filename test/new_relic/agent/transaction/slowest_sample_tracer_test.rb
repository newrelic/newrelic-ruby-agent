# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class SlowestSampleTracerTest < Test::Unit::TestCase
  def setup
    @tracer = NewRelic::Agent::Transaction::SlowestSampleTracer.new
  end

  def test_store_sample
    sample = stub(:duration => 2.0, :threshold => 1.0)
    @tracer.store(sample)
    assert_equal(sample, @tracer.slowest_sample)
  end

  def test_store_new_is_slowest
    old_sample = stub(:duration => 3.0, :threshold => 1.0)
    new_sample = stub(:duration => 4.0, :threshold => 1.0)

    @tracer.store(old_sample)
    @tracer.store(new_sample)

    assert_equal(new_sample, @tracer.slowest_sample)
  end

  def test_store_new_is_faster
    old_sample = stub(:duration => 4.0, :threshold => 1.0)
    new_sample = stub(:duration => 3.0, :threshold => 1.0)

    @tracer.store(old_sample)
    @tracer.store(new_sample)

    assert_equal(old_sample, @tracer.slowest_sample)
  end

  def test_store_does_not_store_if_faster_than_threshold
    old_sample = stub(:duration => 1.0, :threshold => 0.5)
    new_sample = stub(:duration => 2.0, :threshold => 4.0)

    @tracer.store(old_sample)
    @tracer.store(new_sample)

    assert_equal(old_sample, @tracer.slowest_sample)
  end

  def test_harvest_samples
    sample = stub(:duration => 1.0, :threshold => 1.0)
    @tracer.store(sample)

    harvested = @tracer.harvest_samples

    assert_equal([sample], harvested)
  end

  def test_harvest_samples_resets
    sample = stub(:duration => 1.0, :threshold => 1.0)
    @tracer.store(sample)

    @tracer.harvest_samples

    assert_nil(@tracer.slowest_sample)
  end
end
