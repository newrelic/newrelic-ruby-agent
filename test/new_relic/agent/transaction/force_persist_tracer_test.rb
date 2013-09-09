# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Transaction
  class ForcePersistTracerTest < Test::Unit::TestCase
    def setup
      @tracer = ForcePersistTracer.new
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

    def test_intermediate_storage_keeps_N_longest_samples
      samples = (1..100).map { |i| stub(i.to_s, :force_persist => true, :duration => i) }
      samples.each {|s| @tracer.store(s)}

      assert_equal(samples.last(ForcePersistTracer::MAX_SAMPLES), @tracer.samples)
    end
  end
end
