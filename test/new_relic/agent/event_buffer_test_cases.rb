# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/event_buffer'

module NewRelic::Agent::EventBufferTestCases

  # NOTE: Classes including this module must define `buffer_class`; for example:
  #
  # def buffer_class
  #   MyVerySpecialBuffer
  # end

  def test_limits_itself_to_capacity
    buffer = buffer_class.new(10)

    11.times { |i| buffer.append(i) }

    assert_equal(10, buffer.size       )
    assert_equal(11, buffer.num_seen   )
    assert_equal( 1, buffer.num_dropped)
  end

  def test_should_not_discard_items_if_not_needed_when_capacity_is_reset
    buffer = buffer_class.new(10)
    assert_equal(10, buffer.capacity)
    10.times { |i| buffer << i }

    buffer.capacity = 20
    assert_equal(10, buffer.size       )
    assert_equal(20, buffer.capacity   )
    assert_equal(10, buffer.num_seen   )
    assert_equal( 0, buffer.num_dropped)
    assert_equal((0..9).to_a, buffer.to_a)
  end

  def test_reset_should_reset
    buffer = buffer_class.new(10)
    100.times { |i| buffer << i }
    buffer.reset!
    assert_equal(0, buffer.size)
    assert_equal([], buffer.to_a)
  end

  def test_to_a_returns_copy_of_items_array
    buffer = buffer_class.new(5)

    5.times { |i| buffer.append(i) }

    items = buffer.to_a
    items << ['blarg']

    assert_equal([0,1,2,3,4], buffer.to_a)
  end

  def test_reset_resets_stored_items
    buffer = buffer_class.new(5)

    5.times { |i| buffer.append(i) }
    buffer.reset!

    assert_equal([], buffer.to_a)
  end

  def test_buffer_full_works_properly
    buffer = buffer_class.new(5)

    4.times do |i|
      buffer << i
      assert_equal(false, buffer.full?, "#{buffer_class}#append should return false until buffer is full")
    end

    4.times do |i|
      buffer << 'lava'
      assert_equal(true, buffer.full?, "#{buffer_class}#append should return true once buffer is full")
    end
  end

  def test_should_keep_all_samples_up_to_capacity
    buffer = buffer_class.new(100)
    all = []
    100.times do |i|
      buffer << i
      all << i
    end

    assert_equal(100, buffer.size)
    assert_equal(all, buffer.to_a)
  end

  def test_should_discard_items_as_needed_when_capacity_is_reset
    buffer = buffer_class.new(10)
    10.times { |i| buffer << i }

    buffer.capacity = 5
    assert_equal(5, buffer.size)

    # We should have 5 unique values that were all in our original set of 0-9
    assert_equal(5, buffer.to_a.uniq.size)
    allowed_values = (0..9).to_a
    buffer.to_a.each do |v|
      assert_includes(allowed_values, v)
    end
    assert_equal(10, buffer.num_seen   )
    assert_equal( 5, buffer.num_dropped)
  end

  def test_num_seen_counts_all_seen_samples_since_last_reset
    buffer = buffer_class.new(10)
    assert_equal(0, buffer.num_seen)

    20.times { |i| buffer << i }
    assert_equal(20, buffer.num_seen)

    buffer.reset!
    assert_equal(0, buffer.num_seen)
  end

  def test_append_increments_drop_count_when_over_capacity
    buffer = buffer_class.new(5)

    5.times { |i| buffer.append(i) }
    assert_equal(0, buffer.num_dropped)

    5.times { |i| buffer.append(i) }
    assert_equal(5, buffer.num_dropped)
  end

  def test_reset_resets_drop_count
    buffer = buffer_class.new(5)

    10.times { |i| buffer.append(i) }
    assert_equal(5, buffer.num_dropped)

    buffer.reset!
    assert_equal(0, buffer.num_dropped)
  end

  def test_sample_rate
    buffer = buffer_class.new(10)
    assert_equal(0, buffer.sample_rate)

    10.times { buffer << 'x' }
    assert_equal(1.0, buffer.sample_rate)

    10.times { buffer << 'x' }
    assert_equal(0.5, buffer.sample_rate)
  end

  def test_metadata
    buffer = buffer_class.new(5)
    7.times { buffer << 'x' }

    expected = {
      :capacity => 5,
      :seen => 7,
      :captured => 5
    }

    metadata = buffer.metadata
    metadata.delete :captured_lifetime
    metadata.delete :seen_lifetime

    assert_equal expected, metadata
  end
end
