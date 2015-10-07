# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'test/new_relic/agent/event_buffer_test_cases'

module NewRelic::Agent
  class SampledBufferTest < Minitest::Test
    include EventBufferTestCases

    def buffer_class
      SampledBuffer
    end

    def test_replaces_old_entries_when_necessary
      buffer = buffer_class.new(5)

      buffer.expects(:rand).with(6).returns(0)
      buffer.expects(:rand).with(7).returns(1)
      buffer.expects(:rand).with(8).returns(2)
      buffer.expects(:rand).with(9).returns(3)
      buffer.expects(:rand).with(10).returns(4)

      10.times { |i| buffer << i }

      assert_equal([5, 6, 7, 8, 9], buffer.to_a)
    end

    def test_discards_new_entries_when_necessary
      buffer = buffer_class.new(5)

      buffer.expects(:rand).with(6).returns(5)
      buffer.expects(:rand).with(7).returns(6)
      buffer.expects(:rand).with(8).returns(7)
      buffer.expects(:rand).with(9).returns(8)
      buffer.expects(:rand).with(10).returns(9)

      10.times { |i| buffer << i }

      assert_equal([0, 1, 2, 3, 4], buffer.to_a)
    end

    def test_append_returns_whether_item_was_stored
      buffer = buffer_class.new(5)

      buffer.expects(:rand).with(6).returns(5)

      5.times do |i|
        result = buffer.append(i)
        assert(result)
      end

      result = buffer.append('foo')
      refute(result)
    end

    # This test is non-deterministic: there is some (low) probability that it will
    # fail. We repeatedly stream 10 items into a buffer of capacity 5, and verify
    # that each item is included ~50% of the time.
    #
    # Because of the non-determinism, it is possible that we'll want to disable
    # this test. That said, I've thus far been unsuccessful in making it fail, so
    # I'm leaving it here for now.
    def test_should_sample_evenly
      buffer = buffer_class.new(5)
      results = []

      10000.times do
        buffer.reset!
        10.times { |i| buffer << i }
        results << buffer.to_a
      end

      (0...10).each do |v|
        num_results_including_v = results.select { |r| r.include?(v) }.size
        assert_in_delta(0.5, num_results_including_v.to_f / results.size, 0.05)
      end
    end

    def test_seen_lifetime_should_persist_across_resets
      buffer = buffer_class.new(10)

      100.times { |i| buffer << i }
      buffer.reset!
      assert_equal(100, buffer.seen_lifetime)

      100.times { |i| buffer << i }
      buffer.reset!
      assert_equal(200, buffer.seen_lifetime)
    end

    def test_sample_rate_lifetime
      buffer = buffer_class.new(10)
      assert_equal(0, buffer.sample_rate_lifetime)

      10.times { buffer << 'x' }
      buffer.reset!
      assert_equal(1.0, buffer.sample_rate_lifetime)

      30.times { buffer << 'x' }
      buffer.reset!
      assert_equal(0.5, buffer.sample_rate_lifetime)
    end

    def test_append_with_block
      buffer = buffer_class.new(5)
      5.times do |i|
        buffer.append { i }
      end

      assert_equal [0, 1, 2, 3, 4], buffer.to_a
    end

    def test_append_with_block_while_sampling
      buffer = buffer_class.new(5)
      buffer.stubs(:rand).returns(0)

      10.times do |i|
        buffer.append { i }
      end

      assert_equal [9, 1, 2, 3, 4], buffer.to_a
    end

    def test_append_with_block_increments_seen
      buffer = buffer_class.new(5)
      10.times do |i|
        buffer.append { i }
      end

      assert_equal 10, buffer.num_seen
    end

    def test_append_does_not_allow_an_argument_and_block
      assert_raises ArgumentError do
        buffer = buffer_class.new 5
        buffer.append(4) { 5 }
      end
    end
  end
end
