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
          unfreeze_time
          NewRelic::Agent.drop_buffered_data
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

            #clean up traced method stack
            txn.unstub(:segment_complete)
            txn.segment_complete(segment)
          end
        end

        def test_segment_data_is_copied_to_trace
          segment = nil
          segment_name = "Custom/simple/segment"
          in_transaction "test_txn" do
            segment = Transaction.start_segment  segment_name, "Segment/all"
            segment.start
            advance_time 1.0
            segment.finish
          end

          trace = last_transaction_trace
          node = find_node_with_name(trace, segment_name)

          refute_nil node, "Expected trace to have node with name: #{segment_name}"
          assert_equal segment.duration, node.duration
        end

        def test_start_segment
          in_transaction "test_txn" do |txn|
            segment = Transaction.start_segment "Custom/segment/method"
            assert_equal Time.now, segment.start_time
            assert_equal txn, segment.transaction

            advance_time 1
            segment.finish
            assert_equal Time.now, segment.end_time
          end
        end

        def test_start_datastore_segment
          in_transaction "test_txn" do |txn|
            segment = Transaction.start_datastore_segment "SQLite", "insert", "Blog"
            assert_equal Time.now, segment.start_time
            assert_equal txn, segment.transaction

            advance_time 1
            segment.finish
            assert_equal Time.now, segment.end_time
          end
        end

        def test_start_datastore_segment_provides_defaults_without_params
          segment = Transaction.start_datastore_segment
          segment.finish

          assert_equal "Datastore/operation/Unknown/other", segment.name
          assert_equal "Unknown", segment.product
          assert_equal "other", segment.operation
        end

        def test_start_datastore_segment_does_not_record_metrics_outside_of_txn
          segment = Transaction.start_datastore_segment "SQLite", "insert", "Blog"
          segment.start
          advance_time 1
          segment.finish

          refute_metrics_recorded [
            "Datastore/statement/SQLite/Blog/insert",
            "Datastore/operation/SQLite/insert",
            "Datastore/SQLite/allWeb",
            "Datastore/SQLite/all",
            "Datastore/allWeb",
            "Datastore/all"
          ]
        end

        def test_start_segment_with_tracing_disabled_in_transaction
          segment = nil
          in_transaction "test_txn" do |txn|
            NewRelic::Agent.disable_all_tracing do
              segment = Transaction.start_segment "Custom/segment/method", "Custom/all"
              advance_time 1
              segment.finish
            end
          end
          assert_nil segment.transaction, "Did not expect segment to associated with a transaction"
          refute_metrics_recorded ["Custom/segment/method", "Custom/all"]
        end


        def test_current_segment_in_transaction
          in_transaction "test_txn" do |txn|
            assert_equal txn.initial_segment, txn.current_segment
            ds_segment = Transaction.start_datastore_segment "SQLite", "insert", "Blog"
            assert_equal ds_segment, txn.current_segment

            segment = Transaction.start_segment "Custom/basic/segment"
            assert_equal segment, txn.current_segment

            segment.finish
            assert_equal ds_segment, txn.current_segment

            ds_segment.finish
            assert_equal txn.initial_segment, txn.current_segment
          end
        end

        def test_segments_are_properly_parented
          in_transaction "test_txn" do |txn|
            assert_equal nil, txn.initial_segment.parent

            ds_segment = Transaction.start_datastore_segment "SQLite", "insert", "Blog"
            assert_equal txn.initial_segment, ds_segment.parent

            segment = Transaction.start_segment "Custom/basic/segment"
            assert_equal ds_segment, segment.parent

            segment.finish
            ds_segment.finish
          end
        end

        def test_segment_started_oustide_txn_does_not_record_metrics
          segment = Transaction.start_segment "Custom/segment/method", "Custom/all"
          advance_time 1
          segment.finish

          assert_nil segment.transaction, "Did not expect segment to associated with a transaction"
          refute_metrics_recorded ["Custom/segment/method", "Custom/all"]
        end

        def test_start_external_request_segment
          in_transaction "test_txn" do |txn|
            segment = Transaction.start_external_request_segment "Net::HTTP", "http://site.com/endpoint", "GET"
            assert_equal Time.now, segment.start_time
            assert_equal txn, segment.transaction
            assert_equal "Net::HTTP", segment.library
            assert_equal "http://site.com/endpoint", segment.uri.to_s
            assert_equal "GET", segment.procedure

            advance_time 1
            segment.finish
            assert_equal Time.now, segment.end_time
          end
        end

        def test_segment_does_not_record_metrics_outside_of_txn
          segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
          segment.finish

          refute_metrics_recorded [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb",
            ["External/remotehost.com/Net::HTTP/GET", "test"]
          ]
        end

        def test_children_time
          in_transaction "test" do
            segment_a = NewRelic::Agent::Transaction.start_segment "metric a"
            advance_time(0.001)

            segment_b = NewRelic::Agent::Transaction.start_segment "metric b"
            advance_time(0.002)

            segment_c = NewRelic::Agent::Transaction::start_segment "metric c"
            advance_time(0.003)
            segment_c.finish
            assert_equal 0, segment_c.children_time

            advance_time(0.001)

            segment_d = NewRelic::Agent::Transaction.start_segment "metric d"
            advance_time(0.002)
            segment_d.finish
            assert_equal 0, segment_d.children_time

            segment_b.finish
            assert_in_delta(segment_c.duration + segment_d.duration, segment_b.children_time, 0.0001)

            segment_a.finish
            assert_in_delta(segment_b.duration, segment_a.children_time, 0.0001)
          end
        end

        def test_timing_correct_with_record_metrics_false
          in_transaction "test" do
            segment_a = NewRelic::Agent::Transaction.start_segment "metric a"
            advance_time(0.001)

            segment_b = NewRelic::Agent::Transaction.start_segment "metric b"
            segment_b.record_metrics = false
            advance_time(0.002)

            segment_c = NewRelic::Agent::Transaction::start_segment "metric c"
            advance_time(0.003)
            segment_c.finish
            assert_equal 0, segment_c.children_time

            advance_time(0.001)

            segment_b.finish
            assert_in_delta(segment_c.duration, segment_b.children_time, 0.0001)

            segment_a.finish
            assert_in_delta(segment_c.duration, segment_a.children_time, 0.0001)
            assert_in_delta(0.001 + segment_b.exclusive_duration, segment_a.exclusive_duration, 0.0001)
          end
        end

        def test_segments_abides_by_limit_configuration
          limit = Agent.config[:'transaction_tracer.limit_segments']
          txn = in_transaction do
            (limit + 10).times do |n|
              segment = NewRelic::Agent::Transaction.start_segment "MyCustom/segment#{n}"
              segment.finish
            end
          end
          assert_equal limit, txn.segments.size
        end

        def test_segments_retain_exclusive_time_after_surpassing_limit
          with_config(:'transaction_tracer.limit_segments' => 2) do
            segment_a, segment_b, segment_c = nil, nil, nil
            in_transaction do
              advance_time(1)
              segment_a = NewRelic::Agent::Transaction.start_segment 'metric_a'
              advance_time(2)
              segment_b = NewRelic::Agent::Transaction.start_segment 'metric_b'
              advance_time(3)
              segment_c = NewRelic::Agent::Transaction.start_segment 'metric_c'
              advance_time(4)
              segment_c.finish
              segment_b.finish
              segment_a.finish
            end

            assert_equal 2, segment_a.exclusive_duration
            assert_equal 9, segment_a.duration

            assert_equal 3, segment_b.exclusive_duration
            assert_equal 7, segment_b.duration
          end
        end

        def test_segments_over_limit_still_record_metrics
          with_config(:'transaction_tracer.limit_segments' => 2) do
            segment_a, segment_b, segment_c = nil, nil, nil
            in_transaction do
              advance_time(1)
              segment_a = NewRelic::Agent::Transaction.start_segment 'metric_a'
              advance_time(2)
              segment_b = NewRelic::Agent::Transaction.start_segment 'metric_b'
              advance_time(3)
              segment_c = NewRelic::Agent::Transaction.start_segment 'metric_c'
              advance_time(4)
              segment_c.finish
              segment_b.finish
              segment_a.finish
            end

            assert_metrics_recorded ['metric_a', 'metric_b', 'metric_c']
          end
        end

        # The test below documents a failure case. When a transaction has
        # completed, and a segment has not been finished, we will forcibly
        # finish the segment at the end of the transaction. This will cause the
        # exclusive time to be off for the parent of the unfinished segment.
        # This behavior may change over time and there is not reason to preserve
        # it as is. The point of this test is to ensure that the transaction
        # isn't lost entirely. We will log a message at warn level when this
        # unexpected conditon arises.

        def test_unfinished_segment_is_truncated_at_transaction_end_exclusive_times_incorrect
          segment_a, segment_b, segment_c = nil, nil, nil
          in_transaction do
            advance_time(1)
            segment_a = NewRelic::Agent::Transaction.start_segment 'metric_a'
            advance_time(2)
            segment_b = NewRelic::Agent::Transaction.start_segment 'metric_b'
            advance_time(3)
            segment_c = NewRelic::Agent::Transaction.start_segment 'metric_c'
            advance_time(4)
            segment_c.finish
            segment_a.finish
          end

          # the parent has incorrect exclusive_duration since it's child,
          # segment_b, wasn't properly finished
          assert_equal 9, segment_a.exclusive_duration
          assert_equal 9, segment_a.duration

          assert_equal 3, segment_b.exclusive_duration
          assert_equal 7, segment_b.duration

          assert_equal 4, segment_c.exclusive_duration
          assert_equal 4, segment_c.duration
        end
      end
    end
  end
end

