# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Transaction
  class SyntheticsSampleBufferTest < Minitest::Test
    def setup
      @buffer = SyntheticsSampleBuffer.new
    end

    def test_doesnt_store_if_not_synthetics
      sample = stub(:synthetics_resource_id => nil)
      @buffer.store(sample)
      assert_empty @buffer.samples
    end

    def test_stores_if_synthetics
      sample = stub(:synthetics_resource_id => 42)
      @buffer.store(sample)
      assert_equal [sample], @buffer.samples
    end

    def test_applies_limits
      last_sample = nil

      try_count = @buffer.capacity + 1
      try_count.times do |i|
        last_sample = stub(:synthetics_resource_id => i)
        @buffer.store(last_sample)
      end

      assert_equal @buffer.capacity, @buffer.samples.length
      refute_includes @buffer.samples, last_sample
    end
  end
end
