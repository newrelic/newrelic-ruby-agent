# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/heap'

module NewRelic
  module Agent
    class HeapTest < Minitest::Test
      def test_items_can_be_modified_by_accessors
        heap = Heap.new

        heap.push(12)
        heap.push(5)
        heap.push(4)
        heap.push(8)

        assert_equal 5, heap[2]

        heap[2] = 6

        assert_equal 6, heap[2]
      end

      def test_items_inserted_in_proper_order
        heap = Heap.new

        heap.push(12)
        heap.push(5)
        heap.push(4)
        heap.push(8)

        assert_equal [4, 8, 5, 12], heap.to_a
      end

      def test_tree_rebalanced_on_pop
        heap = Heap.new

        heap.push(12)
        heap.push(5)
        heap.push(4)
        heap.push(8)

        heap.pop

        assert_equal [5, 8, 12], heap.to_a
      end

      def test_items_are_popped_in_ascending_order
        heap = Heap.new
        heap.push(12)
        heap.push(5)
        heap.push(4)
        heap.push(8)
        heap.push(30)
        heap.push(7)

        ordered_items = []

        6.times do
          ordered_items << heap.pop
        end

        assert_equal [4, 5, 7, 8, 12, 30], ordered_items
        assert_equal [], heap.to_a
      end

      def test_items_are_popped_in_ascending_order_with_priority_function
        heap = Heap.new {|x| x[:priority] }
        heap.push({priority: 12})
        heap.push({priority: 5})
        heap.push({priority: 4})
        heap.push({priority: 8})
        heap.push({priority: 30})
        heap.push({priority: 7})

        ordered_items = []

        6.times do
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
        heap = Heap.new

        input = (0..1000).to_a
        input.shuffle.each { |i| heap.push(i) }

        output = []
        input.size.times { output << heap.pop }

        assert_equal input, output
        assert_equal [], heap.to_a
      end

      def test_large_heap_odd_number_of_items
        heap = Heap.new

        input = (0..1001).to_a
        input.shuffle.each { |i| heap.push(i) }

        output = []
        input.size.times { output << heap.pop }

        assert_equal input, output
        assert_equal [], heap.to_a
      end
    end
  end
end
