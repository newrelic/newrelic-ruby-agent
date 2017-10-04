# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/transaction/trace_builder'

module NewRelic
  module Agent
    class Transaction
      class TraceBuilderTest < Minitest::Test
        def setup
          freeze_time
        end

        def test_builds_trace_for_transaction
          txn = nil
          state = TransactionState.tl_get
          Transaction.wrap state, "test_txn", :controller do
            txn = state.current_transaction
            advance_time 1
            segment_a = Transaction.start_segment "segment_a"
            segment_a.params[:foo] = "bar"
            advance_time 1
            segment_b = Transaction.start_segment "segment_b"
            advance_time 2
            segment_b.finish
            segment_c = Transaction.start_segment "segment_c"
            advance_time 3
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
          state = TransactionState.tl_get
          Transaction.wrap state, "test_txn", :controller do
            txn = state.current_transaction
            advance_time 1
            Transaction.start_segment "segment_a"
            advance_time 1
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
