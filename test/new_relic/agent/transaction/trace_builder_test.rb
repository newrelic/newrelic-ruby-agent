# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/transaction/trace_builder'

module NewRelic
  module Agent
    class Transaction
      class TraceBuilderTest < Minitest::Test
        def setup
          nr_freeze_process_time
        end

        def test_builds_trace_for_transaction
          txn = nil
          state = Tracer.state
          Tracer.in_transaction name: "test_txn", category: :controller do
            txn = state.current_transaction
            advance_process_time 1
            segment_a = Tracer.start_segment name: "segment_a"
            segment_a.params[:foo] = "bar"
            advance_process_time 1
            segment_b = Tracer.start_segment name: "segment_b"
            advance_process_time 2
            segment_b.finish
            segment_c = Tracer.start_segment name: "segment_c"
            advance_process_time 3
            segment_c.finish
            segment_a.finish
          end

          trace = TraceBuilder.build_trace txn

          root = trace.root_node
          assert_equal "ROOT", root.metric_name
          assert_equal 0.0, root.entry_timestamp
          assert_equal 7.0, root.exit_timestamp

          txn_segment = root.children[0]
          assert_equal "test_txn", txn_segment.metric_name
          assert_equal 0.0, txn_segment.entry_timestamp
          assert_equal 7.0, txn_segment.exit_timestamp

          segment_a = txn_segment.children[0]
          assert_equal "segment_a", segment_a.metric_name
          assert_equal 1.0, segment_a.entry_timestamp
          assert_equal 7.0, segment_a.exit_timestamp
          assert_equal "bar", segment_a.params[:foo]

          segment_b = segment_a.children[0]
          assert_equal "segment_b", segment_b.metric_name
          assert_equal 2.0, segment_b.entry_timestamp
          assert_equal 4.0, segment_b.exit_timestamp

          segment_c = segment_a.children[1]
          assert_equal "segment_c", segment_c.metric_name
          assert_equal 4.0, segment_c.entry_timestamp
          assert_equal 7.0, segment_c.exit_timestamp
        end

        def test_trace_built_if_segment_left_unfinished
          txn = nil
          state = Tracer.state
          Tracer.in_transaction name: "test_txn", category: :controller do
            txn = state.current_transaction
            advance_process_time 1
            Tracer.start_segment name: "segment_a"
            advance_process_time 1
          end

          trace = TraceBuilder.build_trace txn

          root = trace.root_node
          assert_equal "ROOT", root.metric_name
          assert_equal 0.0, root.entry_timestamp
          assert_equal 2.0, root.exit_timestamp

          txn_segment = root.children[0]
          assert_equal "test_txn", txn_segment.metric_name
          assert_equal 0.0, txn_segment.entry_timestamp
          assert_equal 2.0, txn_segment.exit_timestamp

          segment_a = txn_segment.children[0]
          assert_equal "segment_a", segment_a.metric_name
          assert_equal 1.0, segment_a.entry_timestamp
          assert_equal 2.0, segment_a.exit_timestamp
        end
      end
    end
  end
end
