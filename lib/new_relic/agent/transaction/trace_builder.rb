# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/helper'
require 'new_relic/agent/transaction/trace'
require 'new_relic/agent/transaction/trace_node'

module NewRelic
  module Agent
    class Transaction
      module TraceBuilder
        extend self

        def build_trace transaction
          trace = Trace.new transaction.start_time
          trace.root_node.exit_timestamp = transaction.end_time - transaction.start_time
          first, *rest = transaction.segments
          relationship_map = rest.group_by { |s| s.parent }
          process_segment transaction, first, trace.root_node, relationship_map
          trace
        end

        private

        # process_segment builds the tree structure by descending
        # recursively through each segment's children
        def process_segment transaction, segment, parent, relationship_map
          current = create_trace_node transaction, segment
          parent.children << current
          current.parent_node = parent
          if children = relationship_map[segment]
            children.each do |child|
              process_segment transaction, child, current, relationship_map
            end
          end
          current
        end

        def create_trace_node transaction, segment
          relative_start = segment.start_time - transaction.start_time
          relative_end = segment.end_time - transaction.start_time
          TraceNode.new2 segment.name, relative_start, relative_end, segment.params
        end
      end
    end
  end
end
