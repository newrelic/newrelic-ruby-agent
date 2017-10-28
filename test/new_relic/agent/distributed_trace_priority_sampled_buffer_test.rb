# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../test_helper', __FILE__
require 'new_relic/agent/distributed_trace_priority_sampled_buffer'
require 'new_relic/agent/event_buffer_test_cases'

module NewRelic
  module Agent
    class DistributedTracePrioritySampledBufferTest < Minitest::Test
      include EventBufferTestCases

      def buffer_class
        DistributedTracePrioritySampledBuffer
      end

      def test_low_priority_slots_are_tracked
        buffer = buffer_class.new(5)
        5.times { |i| buffer.append i }

        assert_equal (0..4).to_a, low_priority_indices(buffer)
      end

      def test_high_priority_slots_are_tracked
        buffer = buffer_class.new(5)
        5.times { |i| buffer.append_sampled i }

        assert_equal (0..4).to_set, high_priority_indices(buffer)
      end

      def test_low_priority_items_are_discarded_in_favor_of_high_priority_items
        buffer = buffer_class.new(5)
        5.times { |i| buffer.append i }

        assert_equal (0..4).to_a, low_priority_indices(buffer)

        5.upto(9) { |i| assert buffer.append_sampled(i) }

        assert_equal [], low_priority_indices(buffer)
        assert_equal (0..4).to_set, high_priority_indices(buffer)
        assert_equal (5..9).to_set, buffer.to_a.to_set
      end

      def test_sampled_items_not_discarded_in_favor_of_low_priority_items
        buffer = buffer_class.new(5)
        5.times { |i| buffer.append_sampled i }

        assert_equal (0..4).to_set, high_priority_indices(buffer)

        5.upto(9) { |i| refute buffer.append(i) }
        assert_equal [], low_priority_indices(buffer)
        assert_equal (0..4).to_set, high_priority_indices(buffer)
        assert_equal (0..4).to_set, buffer.to_a.to_set
      end

      def high_priority_indices buffer
        buffer.instance_variable_get :@high_priority_indices
      end

      def low_priority_indices buffer
        buffer.instance_variable_get :@low_priority_indices
      end
    end
  end
end
