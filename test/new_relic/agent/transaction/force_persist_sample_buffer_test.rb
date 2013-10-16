# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Transaction
  class ForcePersistSampleBufferTest < Test::Unit::TestCase
    def setup
      @buffer = ForcePersistSampleBuffer.new
    end

    def test_stores_forced_sample
      sample = stub(:force_persist => true)
      @buffer.store(sample)

      assert_equal([sample], @buffer.samples)
    end

    def test_does_not_store_forced_sample
      sample = stub(:force_persist => false)
      @buffer.store(sample)

      assert(@buffer.samples.empty?)
    end

    def test_harvest_samples
      sample = stub(:force_persist => true)
      @buffer.store(sample)

      result = @buffer.harvest_samples

      assert_equal([sample], result)
    end

    def test_harvest_samples_resets
      sample = stub(:force_persist => true)
      @buffer.store(sample)

      @buffer.harvest_samples

      assert(@buffer.samples.empty?)
    end

    def test_intermediate_storage_keeps_N_longest_samples
      samples = (1..100).map { |i| stub(i.to_s, :force_persist => true, :duration => i) }
      samples.each {|s| @buffer.store(s)}

      assert_equal(samples.last(@buffer.capacity), @buffer.samples)
    end
  end
end
