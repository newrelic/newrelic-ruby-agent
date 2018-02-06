# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    # This class implements a min Heap. The first element is always the one with the
    # lowest priority. It is a tree structure that is represented as an array. The
    # relationship between between nodes in the tree and indices in the array are as
    # follows:
    #
    # parent_index      = (child_index -  1) / 2
    # left_child_index  = parent_index * 2 + 1
    # right_child_index = parent_index * 2 + 2
    #
    # the root node is at index 0
    # a node is a leaf node when its index >= length / 2
    #

    class Heap

      # @param [Callable] priority_fn an optional priority function used to
      #   to compute the priority for an item. If it's not supplied priority
      #   will be computed using Comparable.
      def initialize(&priority_fn)
        @items = []
        @priority_fn = priority_fn || ->(x) { x }
      end

      def [](index)
        @items[index]
      end

      def []=(index, value)
        @items[index] = value
      end

      def fix(index)
        parent_index = (index - 1) / 2

        if(parent_index >= 0 && priority(parent_index) > priority(index))
          heapify_up(index)
        else
          child_index = index * 2 + 1

          return if child_index > @items.size - 1

          if(priority(child_index) > priority(child_index + 1))
            child_index += 1
          end

          if(priority(child_index) < priority(index))
            heapify_down(index)
          end
        end
      end

      def push(item)
        @items << item
        heapify_up(@items.size - 1)
      end

      def pop
        swap(0, @items.size - 1)
        item = @items.pop
        heapify_down(0)
        item
      end

      def empty?
        @items.empty?
      end

      def to_a
        @items
      end

      private

      def priority(index)
        @priority_fn.call(@items[index])
      end

      def heapify_up(child_index)
        return if child_index == 0

        parent_index = (child_index - 1) / 2

        if priority(child_index) < priority(parent_index)
          swap(child_index, parent_index)
          heapify_up(parent_index)
        end
      end

      def heapify_down(parent_index)
        child_index = 2 * parent_index + 1
        return if child_index > @items.size - 1

        if(child_index < @items.size - 1 && priority(child_index) > priority(child_index + 1))
          child_index += 1
        end

        if(priority(child_index) < priority(parent_index))
          swap(parent_index, child_index)
          heapify_down(child_index)
        end
      end

      def swap(i, j)
        @items[i], @items[j] = @items[j], @items[i]
      end
    end

  end
end
