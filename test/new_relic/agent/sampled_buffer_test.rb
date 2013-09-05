# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::SampledBufferTest < Test::Unit::TestCase
  def test_should_keep_all_samples_up_to_capacity
    buffer = NewRelic::Agent::SampledBuffer.new(100)
    all = []
    100.times do |i|
      buffer << i
      all << i
    end

    assert_equal(100, buffer.size)
    assert_equal(all, buffer.to_a)
  end

  def test_replaces_old_entries_when_necessary
    buffer = NewRelic::Agent::SampledBuffer.new(5)

    buffer.expects(:rand).with(6).returns(0)
    buffer.expects(:rand).with(7).returns(1)
    buffer.expects(:rand).with(8).returns(2)
    buffer.expects(:rand).with(9).returns(3)
    buffer.expects(:rand).with(10).returns(4)

    10.times { |i| buffer << i }

    assert_equal([5, 6, 7, 8, 9], buffer.to_a)
  end

  def test_discards_new_entries_when_necessary
    buffer = NewRelic::Agent::SampledBuffer.new(5)

    buffer.expects(:rand).with(6).returns(5)
    buffer.expects(:rand).with(7).returns(6)
    buffer.expects(:rand).with(8).returns(7)
    buffer.expects(:rand).with(9).returns(8)
    buffer.expects(:rand).with(10).returns(9)

    10.times { |i| buffer << i }

    assert_equal([0, 1, 2, 3, 4], buffer.to_a)
  end

  # This test is non-deterministic: there is some (low) probability that it will
  # fail. We repeatedly stream 10 items into a buffer of capacity 5, and verify
  # that each item is included ~50% of the time.
  # 
  # Because of the non-determinism, it is possible that we'll want to disable
  # this test. That said, I've thus far been unsuccessful in making it fail, so
  # I'm leaving it here for now.
  def test_should_sample_evenly
    buffer = NewRelic::Agent::SampledBuffer.new(5)
    results = []

    10000.times do
      buffer.reset
      10.times { |i| buffer << i }
      results << buffer.to_a
    end

    (0...10).each do |v|
      num_results_including_v = results.select { |r| r.include?(v) }.size
      assert_in_delta(0.5, num_results_including_v.to_f / results.size, 0.05)
    end
  end

  def test_to_a_should_dup_the_returned_array
    buffer = NewRelic::Agent::SampledBuffer.new(10)

    5.times { |i| buffer << i }

    items = buffer.to_a
    items << 'noodles'

    assert_equal([0, 1, 2, 3, 4], buffer.to_a)
  end

  def test_append_should_return_true_when_buffer_is_full
    buffer = NewRelic::Agent::SampledBuffer.new(5)

    4.times do |i|
      assert_equal(false, buffer.append(i), "SampledBuffer#append should return false until buffer is full")
    end

    4.times do |i|
      assert_equal(true, buffer.append('lava'), "SampledBuffer#append should return true once buffer is full")
    end
  end

  def test_should_discard_items_as_needed_when_capacity_is_reset
    buffer = NewRelic::Agent::SampledBuffer.new(10)
    10.times { |i| buffer << i }

    buffer.capacity = 5
    assert_equal(5, buffer.size)

    # We should have 5 unique values that were all in our original set of 0-9
    assert_equal(5, buffer.to_a.uniq.size)
    allowed_values = (0..9).to_a
    buffer.to_a.each do |v|
      assert_includes(allowed_values, v)
    end
  end

  def test_should_not_discard_items_if_not_needed_when_capacity_is_reset
    buffer = NewRelic::Agent::SampledBuffer.new(10)
    10.times { |i| buffer << i }

    buffer.capacity = 20
    assert_equal(10, buffer.size)
    assert_equal((0..9).to_a, buffer.to_a)
  end

  def test_should_not_exceed_capacity
    buffer = NewRelic::Agent::SampledBuffer.new(100)
    200.times { |i| buffer << i }
    assert_equal(100, buffer.size)
  end

  def test_reset_should_reset
    buffer = NewRelic::Agent::SampledBuffer.new(10)
    100.times { |i| buffer << i }
    buffer.reset
    assert_equal(0, buffer.size)
    assert_equal([], buffer.to_a)
  end

  def test_seen_counts_all_seen_samples_since_last_reset
    buffer = NewRelic::Agent::SampledBuffer.new(10)
    assert_equal(0, buffer.seen)

    20.times { |i| buffer << i }
    assert_equal(20, buffer.seen)

    buffer.reset
    assert_equal(0, buffer.seen)
  end

  def test_seen_lifetime_should_persist_across_resets
    buffer = NewRelic::Agent::SampledBuffer.new(10)

    100.times { |i| buffer << i }
    buffer.reset
    assert_equal(100, buffer.seen_lifetime)

    100.times { |i| buffer << i }
    buffer.reset
    assert_equal(200, buffer.seen_lifetime)
  end

  def test_sample_rate
    buffer = NewRelic::Agent::SampledBuffer.new(10)
    assert_equal(0, buffer.sample_rate)

    10.times { buffer << 'x' }
    assert_equal(1.0, buffer.sample_rate)

    10.times { buffer << 'x' }
    assert_equal(0.5, buffer.sample_rate)
  end

  def test_sample_rate_lifetime
    buffer = NewRelic::Agent::SampledBuffer.new(10)
    assert_equal(0, buffer.sample_rate_lifetime)

    10.times { buffer << 'x' }
    buffer.reset
    assert_equal(1.0, buffer.sample_rate_lifetime)

    30.times { buffer << 'x' }
    buffer.reset
    assert_equal(0.5, buffer.sample_rate_lifetime)
  end
end
