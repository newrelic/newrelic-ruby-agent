# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading

      class BacktraceNode
        attr_reader :file, :method, :line_no, :children
        attr_accessor :runnable_count, :to_prune, :depth

        def initialize(line, parent=nil)
          line =~ /(.*)\:(\d+)\:in `(.*)'/
            @file = $1
          @method = $3
          @line_no = $2.to_i
          @children = []
          @runnable_count = 0
          @to_prune = false
          @depth = 0

          parent.add_child(self) if parent
        end

        def ==(other)
          @file == other.file &&
            @method == other.method &&
            @line_no == other.line_no
        end

        def total_count
          @runnable_count
        end

        # Descending order on count, ascending on depth of nodes
        def order_for_pruning(y)
          [-runnable_count, depth] <=> [-y.runnable_count, y.depth]
        end

        include NewRelic::Coerce

        def to_array
          [[
            string(@file),
            string(@method),
            int(@line_no)
          ],
            int(@runnable_count),
            0,
            @children.map {|c| c.to_array}]
        end

        def add_child(child)
          child.depth = @depth + 1
          @children << child unless @children.include? child
        end

        def prune!
          BacktraceNode.prune!(@children)
        end

        def self.prune!(kids)
          kids.delete_if { |child| child.to_prune }
          kids.each { |child| child.prune! }
        end
      end

    end
  end
end
