# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/heap'

module NewRelic
  module Agent
    class HeapTest < Minitest::Test
      def test_items_inserted_in_proper_order
        heap = Heap.new [12, 5, 4, 8]

        assert_equal [4, 8, 5, 12], heap.to_a
      end

      def test_tree_rebalanced_on_pop
        heap = Heap.new [12, 5, 4, 8]
        heap.pop

        assert_equal [5, 8, 12], heap.to_a
      end

      def test_items_can_be_modified_by_accessors
        heap = Heap.new [12, 5, 4, 8]

        assert_equal 5, heap[2]

        heap[2] = 6

        assert_equal 6, heap[2]
      end

      def test_fix_bubbles_up
        heap = Heap.new [12, 5, 4, 8, 30, 7]

        heap[1] = 1
        heap.fix(1)

        ordered_items = []

        until heap.empty?
          ordered_items << heap.pop
        end

        assert_equal [1, 4, 5, 7, 12, 30], ordered_items
        assert_equal [], heap.to_a
      end

      def test_fix_bubbles_up_large_heap
        heap = Heap.new((1..100).to_a.shuffle)

        replaced_value = heap[99]
        heap[99] = 0
        heap.fix(99)

        ordered_items = []

        until heap.empty?
          ordered_items << heap.pop
        end

        assert_equal (0..100).to_a - [replaced_value], ordered_items
        assert_equal [], heap.to_a
      end

      def test_fix_bubbles_down
        heap = Heap.new [12, 5, 4, 8, 30, 7]

        heap[1] = 50
        heap.fix(1)

        ordered_items = []

        until heap.empty?
          ordered_items << heap.pop
        end

        assert_equal [4, 5, 7, 12, 30, 50], ordered_items
        assert_equal [], heap.to_a
      end

      def test_fix_bubbles_down_large_heap
        heap = Heap.new((1..100).to_a.shuffle)

        heap[0] = 101
        heap.fix(0)

        ordered_items = []

        until heap.empty?
          ordered_items << heap.pop
        end

        assert_equal (2..101).to_a, ordered_items
        assert_equal [], heap.to_a
      end

      def test_fix_leaves_item_if_heap_rule_satisfied
        heap = Heap.new [12, 5, 4, 8, 30, 7]

        heap[1] = 9
        heap.fix(1)

        assert_equal 9, heap[1]

        ordered_items = []

        until heap.empty?
          ordered_items << heap.pop
        end

        assert_equal [4, 5, 7, 9, 12, 30], ordered_items
        assert_equal [], heap.to_a
      end

      def test_items_are_popped_in_ascending_order
        heap = Heap.new [12, 5, 4, 8, 30, 7]

        ordered_items = []

        until heap.empty?
          ordered_items << heap.pop
        end

        assert_equal [4, 5, 7, 8, 12, 30], ordered_items
        assert_equal [], heap.to_a
      end

      def test_items_are_popped_in_ascending_order_with_priority_function
        items = [
          {priority: 12},
          {priority: 5},
          {priority: 4},
          {priority: 8},
          {priority: 30},
          {priority: 7}
        ]

        heap = Heap.new(items) {|x| x[:priority] }

        ordered_items = []

        until heap.empty?
          ordered_items << heap.pop
        end

        expected = [
          {priority: 4},
          {priority: 5},
          {priority: 7},
          {priority: 8},
          {priority: 12},
          {priority: 30}
        ]

        assert_equal expected, ordered_items
        assert_equal [], heap.to_a
      end

      def test_large_heap_even_number_of_items
        heap = Heap.new((0..100).to_a.shuffle)

        output = []
        until heap.empty?
          output << heap.pop
        end

        assert_equal (0..100).to_a, output
        assert_equal [], heap.to_a
      end

      def test_large_heap_odd_number_of_items
       heap = Heap.new((0..101).to_a.shuffle)

        output = []
        until heap.empty?
          output << heap.pop
        end

        assert_equal (0..101).to_a, output
        assert_equal [], heap.to_a
      end
    end
  end
end
