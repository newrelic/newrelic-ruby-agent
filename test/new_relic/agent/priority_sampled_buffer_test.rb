# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../test_helper', __FILE__
require 'new_relic/agent/priority_sampled_buffer'
require 'new_relic/agent/event_buffer_test_cases'

module NewRelic::Agent
  class PrioritySampledBufferTest < Minitest::Test
    def test_keeps_events_of_highest_priority_when_over_capacity
      buffer = PrioritySampledBuffer.new(5)

      10.times { |i| buffer.append(event: {priority: i}) }

      expected = (5..9).map{ |i| {priority: i} }

      assert_equal(5, buffer.size)
      assert_equal_unordered(expected, buffer.to_a)
    end

    def test_block_is_evaluated_based_on_priority
      buffer = PrioritySampledBuffer.new(5)

      5.upto(9) { |i| buffer.append(event: {priority: i}) }

      buffer.append(priority: 4) { raise "This should not be evaluated" }

      expected = (5..9).map{ |i| {priority: i} }
      assert_equal(5, buffer.size)
      assert_equal_unordered(expected, buffer.to_a)
    end

    def test_limits_itself_to_capacity
      buffer = PrioritySampledBuffer.new(10)

      11.times { |i| buffer.append(event: {priority: i}) }

      assert_equal(10, buffer.size       )
      assert_equal(11, buffer.num_seen   )
      assert_equal( 1, buffer.num_dropped)
    end

    def test_should_not_discard_items_if_not_needed_when_capacity_is_reset
      buffer = PrioritySampledBuffer.new(10)
      assert_equal(10, buffer.capacity)
      10.times { |i| buffer.append(event: {priority: i}) }

      expected = (0..9).map{ |i| {priority: i}}

      buffer.capacity = 20
      assert_equal(10, buffer.size       )
      assert_equal(20, buffer.capacity   )
      assert_equal(10, buffer.num_seen   )
      assert_equal( 0, buffer.num_dropped)
      assert_equal(expected, buffer.to_a)
    end
  end
end
