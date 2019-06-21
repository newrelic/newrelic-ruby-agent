# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../test_helper', __FILE__
require 'new_relic/agent/priority_sampled_buffer'

module NewRelic::Agent
  class PrioritySampledBufferTest < Minitest::Test
    def test_keeps_events_of_highest_priority_when_over_capacity
      buffer = PrioritySampledBuffer.new(5)

      10.times { |i| buffer.append(event: create_event(priority: i)) }

      expected = (5..9).map{ |i| create_event(priority: i) }

      assert_equal(5, buffer.size)
      assert_equal_unordered(expected, buffer.to_a)
    end

    def test_block_is_evaluated_based_on_priority
      buffer = PrioritySampledBuffer.new(5)

      events = create_events(5..9)
      events.each { |e| buffer.append(event: e) }

      buffer.append(event: create_event(priority: 4)) { raise "This should not be evaluated" }

      assert_equal(5, buffer.size)
      assert_equal_unordered(events, buffer.to_a)
    end

    def test_limits_itself_to_capacity
      buffer = PrioritySampledBuffer.new(10)

      11.times { |i| buffer.append(event: create_event(priority: i)) }

      assert_equal(10, buffer.size       )
      assert_equal(11, buffer.num_seen   )
      assert_equal( 1, buffer.num_dropped)
    end

    def test_should_not_discard_items_if_not_needed_when_capacity_is_reset
      buffer = PrioritySampledBuffer.new(10)
      assert_equal(10, buffer.capacity)

      events = create_events(1..10)
      events.each { |e| buffer.append(event: e) }

      buffer.capacity = 20
      assert_equal(10, buffer.size       )
      assert_equal(20, buffer.capacity   )
      assert_equal(10, buffer.num_seen   )
      assert_equal( 0, buffer.num_dropped)
      assert_equal(events, buffer.to_a)
    end

    def test_reset_should_reset
      buffer = PrioritySampledBuffer.new(10)
      100.times { |i| buffer.append(event: create_event(priority: i)) }
      buffer.reset!
      assert_equal(0, buffer.size)
      assert_equal([], buffer.to_a)
    end

    def test_to_a_returns_copy_of_items_array
      buffer = PrioritySampledBuffer.new(5)

      events = create_events(0..4)
      events.each { |e| buffer.append(event: e) }

      items = buffer.to_a
      items << create_event(priority: "blarg")

      assert_equal(events, buffer.to_a)
    end

    def test_reset_resets_stored_items
      buffer = PrioritySampledBuffer.new(5)

      events = create_events(0..4)
      events.each { |e| buffer.append(event: e) }

      buffer.reset!

      assert_equal([], buffer.to_a)
    end

    def test_buffer_full_works_properly
      buffer = PrioritySampledBuffer.new(5)

      4.times do |i|
        buffer.append(event: create_event(priority: i))
        assert_equal(false, buffer.full?, "#PrioritySampledBuffer#append should return false until buffer is full")
      end

      4.times do |i|
        buffer.append(event: create_event(priority: i))
        assert_equal(true, buffer.full?, "#PrioritySampledBuffer#append should return true once buffer is full")
      end
    end

    def test_should_keep_all_samples_up_to_capacity
      buffer = PrioritySampledBuffer.new(100)
      all = []

      create_events(1..100).each do |event|
        buffer.append(event: event)
        all << event
      end

      assert_equal(100, buffer.size)
      assert_equal(all, buffer.to_a)
    end

    def test_should_discard_items_as_needed_when_capacity_is_reset
      buffer = PrioritySampledBuffer.new(10)
      10.times { |i| buffer.append(event: create_event(priority: i)) }

      buffer.capacity = 5
      assert_equal(5, buffer.size)

      expected = (5..9).map{ |i| create_event(priority: i)}

      assert_equal_unordered(expected, buffer.to_a)
      assert_equal(10, buffer.num_seen   )
      assert_equal( 5, buffer.num_dropped)
    end

    def test_num_seen_counts_all_seen_samples_since_last_reset
      buffer = PrioritySampledBuffer.new(10)
      assert_equal(0, buffer.num_seen)

      20.times { |i| buffer.append(event: create_event(priority: i)) }
      assert_equal(20, buffer.num_seen)

      buffer.reset!
      assert_equal(0, buffer.num_seen)
    end

    def test_append_increments_drop_count_when_over_capacity
      buffer = PrioritySampledBuffer.new(5)

      5.times { |i| buffer.append(event: create_event(priority: i)) }
      assert_equal(0, buffer.num_dropped)

      5.times { |i| buffer.append(event: create_event(priority: i)) }
      assert_equal(5, buffer.num_dropped)
    end

    def test_append_with_zero_capacity
      buffer = PrioritySampledBuffer.new 0

      buffer.append event: create_event

      assert_equal 1, buffer.num_dropped
      assert_equal 0, buffer.size

      assert_equal 1, buffer.seen_lifetime
      assert_equal 0, buffer.captured_lifetime
    end

    def test_reset_resets_drop_count
      buffer = PrioritySampledBuffer.new(5)

      10.times { |i| buffer.append(event: create_event(priority: i)) }
      assert_equal(5, buffer.num_dropped)

      buffer.reset!
      assert_equal(0, buffer.num_dropped)
    end

    def test_sample_rate
      buffer = PrioritySampledBuffer.new(10)
      assert_equal(0, buffer.sample_rate)

      10.times { |i| buffer.append(event: create_event(priority: i)) }
      assert_equal(1.0, buffer.sample_rate)

      10.times { |i| buffer.append(event: create_event(priority: i)) }
      assert_equal(0.5, buffer.sample_rate)
    end

    def test_metadata
      buffer = PrioritySampledBuffer.new(5)
      7.times { |i| buffer.append(event: create_event(priority: i)) }

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

    def test_seen_lifetime_should_persist_across_resets
      buffer = PrioritySampledBuffer.new(10)

      100.times { |i| buffer.append(event: create_event(priority: i)) }
      buffer.reset!
      assert_equal(100, buffer.seen_lifetime)

      100.times { |i| buffer.append(event: create_event(priority: i)) }
      buffer.reset!
      assert_equal(200, buffer.seen_lifetime)
    end

    def test_sample_rate_lifetime
      buffer = PrioritySampledBuffer.new(10)
      assert_equal(0, buffer.sample_rate_lifetime)

      10.times { |i| buffer.append(event: create_event(priority: i)) }
      buffer.reset!

      assert_equal(1.0, buffer.sample_rate_lifetime)

      30.times { |i| buffer.append(event: create_event(priority: i)) }
      buffer.reset!
      assert_equal(0.5, buffer.sample_rate_lifetime)
    end

    # Our event types all are arrays of three hashes. This method creates
    # a minimal representation of that structure that has the essentials
    # for this test file.
    def create_event(priority: nil, name: nil)
      name ||= "event_#{priority}"
      [{"priority" => priority, "name" => name}, {}, {}]
    end

    def create_events(priorities)
      priorities.map { |i| create_event(priority: i)}
    end
  end
end
