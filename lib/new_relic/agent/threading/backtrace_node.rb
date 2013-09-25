# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Threading

      class BacktraceNode
        attr_reader :file, :method, :line_no, :children, :raw_line
        attr_accessor :runnable_count, :depth

        def initialize(line)
          if line
            @raw_line = line
            @root = false
          else
            @root = true
          end

          @children = []
          @runnable_count = 0
          @depth = 0
        end

        def root?
          @root
        end

        def empty?
          root? && @children.empty?
        end

        def find(raw_line)
          @children.find { |child| child.raw_line == raw_line }
        end

        def ==(other)
          (
            (root? && other.root? || @raw_line == other.raw_line) &&
            (
              @depth == other.depth &&
              @runnable_count == other.runnable_count
            )
          )
        end

        def total_count
          @runnable_count
        end

        def aggregate(backtrace)
          current = self

          backtrace.reverse_each do |frame|
            existing_node = current.find(frame)
            if existing_node
              node = existing_node
            else
              node = Threading::BacktraceNode.new(frame)
              current.add_child_unless_present(node)
            end

            node.runnable_count += 1
            current = node
          end
        end

        # Descending order on count, ascending on depth of nodes
        def <=>(other)
          [-runnable_count, depth] <=> [-other.runnable_count, other.depth]
        end

        def flatten
          initial = self.root? ? [] : [self]
          @children.inject(initial) { |all, child| all.concat(child.flatten) }
        end

        include NewRelic::Coerce

        def to_array
          child_arrays = @children.map { |c| c.to_array }
          return child_arrays if root?
          file, method, line = parse_backtrace_frame(@raw_line)
          [
            [
              string(file),
              string(method),
              int(line)
            ],
            int(@runnable_count),
            0,
            child_arrays
          ]
        end

        def add_child_unless_present(child)
          child.depth = @depth + 1
          @children << child unless @children.include? child
        end

        def prune!(targets)
          @children.delete_if { |child| targets.include?(child) }
          @children.each { |child| child.prune!(targets) }
        end

        def dump_string(indent=0)
          file, method, line = parse_backtrace_frame(@raw_line)
          result = "#{" " * indent}#<BacktraceNode:#{object_id} [#{@runnable_count}] #{@file}:#{@line_no} in #{@method}>"
          child_results = @children.map { |c| c.dump_string(indent+2) }.join("\n")
          result << "\n" unless child_results.empty?
          result << child_results
        end

        # Returns [filename, method, line number]
        def parse_backtrace_frame(frame)
          frame =~ /(.*)\:(\d+)\:in `(.*)'/
          [$1, $3, $2] # sic
        end
      end

    end
  end
end
