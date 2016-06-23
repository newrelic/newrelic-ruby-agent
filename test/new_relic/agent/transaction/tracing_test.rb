# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class Transaction
      class TracingTest < Minitest::Test
        def setup
          freeze_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_segment_without_transaction_records_metrics
          segment = Transaction.start_segment  "Custom/simple/segment", "Segment/all"
          segment.start
          advance_time 1.0
          segment.finish

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_bound_to_transaction_records_metrics
          in_transaction "test_txn" do
            segment = Transaction.start_segment  "Custom/simple/segment", "Segment/all"
            segment.start
            advance_time 1.0
            segment.finish

            refute_metrics_recorded ["Custom/simple/segment", "Segment/all"]
          end

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_bound_to_transaction_invokes_complete_callback_when_finished
          in_transaction "test_txn" do |txn|
            segment = Transaction.start_segment  "Custom/simple/segment", "Segment/all"
            txn.expects(:segment_complete).with(segment)
            segment.start
            advance_time 1.0
            segment.finish
          end
        end

        def test_segment_bound_to_transaction_is_added_to_trace
          segment_name = "Custom/simple/segment"
          in_transaction "test_txn" do
            segment = Transaction.start_segment  segment_name, "Segment/all"
            segment.start
            advance_time 1.0
            segment.finish
          end

          trace = last_transaction_trace
          refute_nil find_node_with_name(trace, segment_name), "Expected trace to have node with name: #{segment_name}"
        end
      end
    end
  end
end

