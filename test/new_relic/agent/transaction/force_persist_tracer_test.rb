# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class ForcePersistTracerTest < Test::Unit::TestCase
  def setup
    @tracer = NewRelic::Agent::Transaction::ForcePersistTracer.new
  end

  def test_stores_forced_sample
    sample = stub(:force_persist => true)
    @tracer.store(sample)

    assert_equal([sample], @tracer.samples)
  end

  def test_does_not_store_forced_sample
    sample = stub(:force_persist => false)
    @tracer.store(sample)

    assert(@tracer.samples.empty?)
  end

  def test_harvest_samples
    sample = stub(:force_persist => true)
    @tracer.store(sample)

    result = @tracer.harvest_samples

    assert_equal([sample], result)
  end

  def test_harvest_samples_resets
    sample = stub(:force_persist => true)
    @tracer.store(sample)

    @tracer.harvest_samples

    assert(@tracer.samples.empty?)
  end
end
