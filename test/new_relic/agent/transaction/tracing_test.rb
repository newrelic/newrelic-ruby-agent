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
          nr_freeze_time
          NewRelic::Agent.drop_buffered_data
        end

        def teardown
          nr_unfreeze_time
          NewRelic::Agent.drop_buffered_data
        end

        def test_segment_bound_to_transaction_records_metrics
          in_transaction "test_txn" do
            segment = Tracer.start_segment(
              name: "Custom/simple/segment",
              unscoped_metrics: "Segment/all"
            )
            segment.start
            advance_time 1.0
            segment.finish

            refute_metrics_recorded ["Custom/simple/segment", "Segment/all"]
          end

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_bound_to_transaction_invokes_complete_callback_when_finished
          in_transaction "test_txn" do |txn|
            segment = Tracer.start_segment(
              name: "Custom/simple/segment",
              unscoped_metrics: "Segment/all"
            )
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
            segment = Tracer.start_segment(
              name: segment_name,
              unscoped_metrics: "Segment/all"
            )
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
            segment = Tracer.start_segment name: "Custom/segment/method"
            assert_equal Time.now, segment.start_time
            assert_equal txn, segment.transaction

            advance_time 1
            segment.finish
            assert_equal Time.now, segment.end_time
          end
        end

        def test_start_segment_with_time_override
          start_time = Time.now
          advance_time 2

          in_transaction "test_txn" do |txn|
            segment = Tracer.start_segment(
              name: "Custom/segment/method",
              start_time: start_time
            )

            advance_time 1
            segment.finish

            assert_equal start_time, segment.start_time
          end
        end

        def test_start_datastore_segment
          in_transaction "test_txn" do |txn|
            segment = Tracer.start_datastore_segment(
              product: "SQLite",
              operation: "insert",
              collection: "Blog"
            )
            assert_equal Time.now, segment.start_time
            assert_equal txn, segment.transaction

            advance_time 1
            segment.finish
            assert_equal Time.now, segment.end_time
          end
        end

        def test_start_datastore_segment_provides_defaults_without_params
          segment = Tracer.start_datastore_segment
          segment.finish

          assert_equal "Datastore/operation/Unknown/other", segment.name
          assert_equal "Unknown", segment.product
          assert_equal "other", segment.operation
        end

        def test_start_datastore_segment_does_not_record_metrics_outside_of_txn
          segment = Tracer.start_datastore_segment(
              product: "SQLite",
              operation: "insert",
              collection: "Blog"
          )
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
              segment = Tracer.start_segment(
                name:"Custom/segment/method",
                unscoped_metrics: "Custom/all"
              )
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
            ds_segment = Tracer.start_datastore_segment(
              product: "SQLite",
              operation: "insert",
              collection: "Blog"
            )
            assert_equal ds_segment, txn.current_segment

            segment = Tracer.start_segment name: "Custom/basic/segment"
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

            ds_segment = Tracer.start_datastore_segment(
              product: "SQLite",
              operation: "insert",
              collection: "Blog"
            )
            assert_equal txn.initial_segment, ds_segment.parent

            segment = Tracer.start_segment name: "Custom/basic/segment"
            assert_equal ds_segment, segment.parent

            segment.finish
            ds_segment.finish
          end
        end

        def test_segment_started_oustide_txn_does_not_record_metrics
          segment = Tracer.start_segment(
            name:"Custom/segment/method",
            unscoped_metrics: "Custom/all"
          )
          advance_time 1
          segment.finish

          assert_nil segment.transaction, "Did not expect segment to associated with a transaction"
          refute_metrics_recorded ["Custom/segment/method", "Custom/all"]
        end

        def test_start_external_request_segment
          in_transaction "test_txn" do |txn|
            segment = Tracer.start_external_request_segment(
              library: "Net::HTTP",
              uri: "http://site.com/endpoint",
              procedure: "GET"
            )
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
          segment = Tracer.start_external_request_segment(
            library: "Net::HTTP",
            uri: "http://remotehost.com/blogs/index",
            procedure: "GET"
          )
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
          segment_a, segment_b, segment_c, segment_d = nil, nil, nil, nil

          in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time(0.001)

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time(0.002)

            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"
            advance_time(0.003)
            segment_c.finish

            advance_time(0.001)

            segment_d = NewRelic::Agent::Tracer.start_segment name: "metric d"
            advance_time(0.002)
            segment_d.finish

            segment_b.finish
            segment_a.finish
          end

          assert_equal 0, segment_c.children_time
          assert_equal 0, segment_d.children_time
          assert_in_delta(segment_c.duration + segment_d.duration, segment_b.children_time, 0.0001)
          assert_in_delta(segment_b.duration, segment_a.children_time, 0.0001)
        end

        def test_segments_abides_by_limit_configuration
          limit = Agent.config[:'transaction_tracer.limit_segments']
          txn = in_transaction do
            (limit + 10).times do |n|
              segment = NewRelic::Agent::Tracer.start_segment name: "MyCustom/segment#{n}"
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
              segment_a = NewRelic::Agent::Tracer.start_segment name: 'metric_a'
              advance_time(2)
              segment_b = NewRelic::Agent::Tracer.start_segment name: 'metric_b'
              advance_time(3)
              segment_c = NewRelic::Agent::Tracer.start_segment name: 'metric_c'
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
              segment_a = NewRelic::Agent::Tracer.start_segment name: 'metric_a'
              advance_time(2)
              segment_b = NewRelic::Agent::Tracer.start_segment name: 'metric_b'
              advance_time(3)
              segment_c = NewRelic::Agent::Tracer.start_segment name: 'metric_c'
              advance_time(4)
              segment_c.finish
              segment_b.finish
              segment_a.finish
            end

            assert_metrics_recorded ['metric_a', 'metric_b', 'metric_c']
          end
        end

        def test_should_not_collect_nodes_beyond_limit
          with_config(:'transaction_tracer.limit_segments' => 3) do
            in_transaction do
              %w[ wheat challah semolina ].each do |bread|
                s = NewRelic::Agent::Tracer.start_datastore_segment
                s.notice_sql("SELECT * FROM sandwiches WHERE bread = '#{bread}'")
                s.finish
              end
            end

            last_sample = last_transaction_trace

            assert_equal 3, last_sample.count_nodes

            expected_sql = "SELECT * FROM sandwiches WHERE bread = 'challah'"
            deepest_node = find_last_transaction_node(last_sample)
            assert_equal([], deepest_node.children)
            assert_equal(expected_sql, deepest_node[:sql].sql)
          end
        end

        # The test below documents a failure case. When a transaction has
        # completed, and a segment has not been finished, we will forcibly
        # finish the segment at the end of the transaction. This will cause the
        # exclusive time to be off for the parent of the unfinished segment.
        # This behavior may change over time and there is no reason to preserve
        # it as is. The point of this test is to ensure that the transaction
        # isn't lost entirely. We will log a message at warn level when this
        # unexpected conditon arises.

        def test_unfinished_segment_is_truncated_at_transaction_end_exclusive_times_incorrect
          segment_a, segment_b, segment_c = nil, nil, nil
          in_transaction do
            advance_time(1)
            segment_a = NewRelic::Agent::Tracer.start_segment name: 'metric_a'
            advance_time(2)
            segment_b = NewRelic::Agent::Tracer.start_segment name: 'metric_b'
            advance_time(3)
            segment_c = NewRelic::Agent::Tracer.start_segment name: 'metric_c'
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

        def test_large_transaction_trace
          config = {
            :'transaction_tracer.enabled' => true,
            :'transaction_tracer.transaction_threshold' => 0,
            :'transaction_tracer.limit_segments' => 100
          }
          with_config(config) do

            in_transaction 'test_txn' do
              110.times do |i|
                segment = NewRelic::Agent::Tracer.start_segment name: "segment_#{i}"
                segment.finish
              end
            end

            sample = last_transaction_trace

            # Verify that the TT stopped recording after 100 nodes
            assert_equal(100, sample.count_nodes)
          end
        end

        def test_txn_not_recorded_when_tracing_is_disabled
          with_config :'transaction_tracer.enabled' => false do
            in_transaction 'dont_trace_this' do
              segment = NewRelic::Agent::Tracer.start_segment name: 'seg'
              segment.finish
            end
          end

          assert_nil last_transaction_trace
        end

        def test_trace_should_log_segment_limit_reached_once
          with_config(:'transaction_tracer.limit_segments' => 3) do
            in_transaction do |txn|
              expects_logging(:debug, includes("Segment limit"))
              8.times {|i| NewRelic::Agent::Tracer.start_segment name: "segment_#{i}" }
            end
          end
        end

        def test_threshold_recorded_for_trace
          with_config :'transaction_tracer.transaction_threshold' => 2.0 do
            in_transaction {}
            trace = last_transaction_trace
            assert_equal 2.0, trace.threshold
          end
        end

        def test_sets_start_time_from_api
          t = Time.now

          in_transaction do |txn|

            segment = NewRelic::Agent::Tracer.start_segment(
              name: "segment_a",
              start_time: t
            )
            segment.finish

            assert_equal t, segment.start_time
          end
        end

        # The following three tests will build the following trace
        #          test_txn
        #              |
        #            segment_a
        #            /     \
        #      segment_b  segment_c

        def test_flexible_parenting_segment
          in_transaction 'test_txn' do
            segment_a = NewRelic::Agent::Tracer.start_segment name: 'segment_a'
            segment_b = NewRelic::Agent::Tracer.start_segment name: 'segment_b'
            segment_c = NewRelic::Agent::Tracer.start_segment(
              name: 'segment_a',
              parent: segment_a
            )
            segment_c.finish
            segment_b.finish
            segment_a.finish

            assert_equal segment_a, segment_b.parent
            assert_equal segment_a, segment_c.parent
          end
        end

        def test_flexible_parenting_datastore_segment
          in_transaction 'test_txn' do
            segment_a = NewRelic::Agent::Tracer.start_segment name: 'segment_a'
            segment_b = NewRelic::Agent::Tracer.start_segment name: 'segment_b'
            segment_c = NewRelic::Agent::Tracer.start_datastore_segment(
              product: "SQLite",
              operation: "Select",
              collection: "blogs",
              parent: segment_a
            )
            segment_c.finish
            segment_b.finish
            segment_a.finish

            assert_equal segment_a, segment_b.parent
            assert_equal segment_a, segment_c.parent
          end
        end

        def test_flexible_parenting_external_request_segment
          in_transaction 'test_txn' do
            segment_a = NewRelic::Agent::Tracer.start_segment name: 'segment_a'
            segment_b = NewRelic::Agent::Tracer.start_segment name: 'segment_b'
            segment_c = NewRelic::Agent::Tracer.start_external_request_segment(
              library: "MyLib",
              uri: "https://blog.newrelic.com",
              procedure: "GET",
              parent: segment_a
            )
            segment_c.finish
            segment_b.finish
            segment_a.finish

            assert_equal segment_a, segment_b.parent
            assert_equal segment_a, segment_c.parent
          end
        end

        def test_flexible_parenting_message_broker_segment
          in_transaction 'test_txn' do
            segment_a = NewRelic::Agent::Tracer.start_segment name: 'segment_a'
            segment_b = NewRelic::Agent::Tracer.start_segment name: 'segment_b'
            segment_c = NewRelic::Agent::Tracer.start_message_broker_segment(
              action: :produce,
              library: "RabbitMQ",
              destination_type: :exchange,
              destination_name: "Default",
              parent: segment_a
            )
            segment_c.finish
            segment_b.finish
            segment_a.finish

            assert_equal segment_a, segment_b.parent
            assert_equal segment_a, segment_c.parent
          end
        end


        # The following three tests will build the following trace.
        # Segments b and c are disjoint, but segments e and f overlap.
        #                       test_txn
        #                     /          \
        #            segment_a            segment_d
        #            /     \                /      \
        #      segment_b  segment_c     segment_e segment_f

        def test_parent_identifies_concurrent_children
          in_transaction 'test_txn' do
            segment_a = NewRelic::Agent::Tracer.start_segment name: 'segment_a'
            segment_b = NewRelic::Agent::Tracer.start_segment name: 'segment_b'
            segment_b.finish
            segment_c = NewRelic::Agent::Tracer.start_segment name: 'segment_c'
            segment_c.finish
            segment_a.finish

            segment_d = NewRelic::Agent::Tracer.start_segment name: 'segment_d'
            segment_e = NewRelic::Agent::Tracer.start_segment name: 'segment_e'
            segment_f = NewRelic::Agent::Tracer.start_segment(
              name: 'segment_f',
              parent: segment_d
            )
            segment_d.finish
            segment_f.finish
            segment_e.finish

            refute segment_a.concurrent_children?
            refute segment_b.concurrent_children?
            refute segment_c.concurrent_children?
            assert segment_d.concurrent_children?
            refute segment_e.concurrent_children?
            refute segment_f.concurrent_children?
          end
        end

        # B, C, D are children of A and are running concurrently. D ends after
        # A finishes. Here is a timeline to illustrate the situation:
        # 0  1  2  3  4  5  6  7  8  9  10 11 12
        #  _________________
        # |        A        |
        #        ________
        #       |    B   |
        #           ________
        #          |    C   |
        #              _______________________
        #             |     D                 |

        def test_concurrent_durations
          segment_a, segment_b, segment_c, segment_d = nil, nil, nil, nil

          in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 2

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 1

            segment_c = NewRelic::Agent::Tracer.start_segment(
              name: "metric c",
              parent: segment_a
            )

            advance_time 1

            segment_d = NewRelic::Agent::Tracer.start_segment(
              name: "metric d",
              parent: segment_a
            )

            advance_time 1
            segment_b.finish

            advance_time 1
            segment_c.finish
            segment_a.finish

            advance_time 6
            segment_d.finish
          end

          assert_equal 6.0, segment_a.duration
          assert_equal 2.0, segment_a.exclusive_duration

          assert_equal 3.0, segment_b.duration
          assert_equal 3.0, segment_b.exclusive_duration

          assert_equal 3.0, segment_c.duration
          assert_equal 3.0, segment_c.exclusive_duration

          assert_equal 8.0, segment_d.duration
          assert_equal 8.0, segment_d.exclusive_duration
        end

        # B and C are children of A and are running serially. C ends after
        # A finishes. Here is a timeline to illustrate the situation:
        # 0  1  2  3  4  5  6  7  8  9  10
        #  _________________
        # |        A        |
        #     _____
        #    | B   |
        #           ____________________
        #          |    C               |

        def test_child_segment_ends_after_parent_durations_correct
          segment_a, segment_b, segment_c = nil, nil, nil

          in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 1

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 2

            segment_b.finish
            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"

            advance_time 3
            segment_a.finish

            advance_time 4
            segment_c.finish
          end

          assert_equal 6.0, segment_a.duration
          assert_equal 1.0, segment_a.exclusive_duration

          assert_equal 2.0, segment_b.duration
          assert_equal 2.0, segment_b.exclusive_duration

          assert_equal 7.0, segment_c.duration
          assert_equal 7.0, segment_c.exclusive_duration
        end

        # B, C, D are children of A. C and D are running concurrently after B completes.
        # D ends after A finishes. Here is a timeline to illustrate the situation:
        # 0  1  2  3  4  5  6  7  8  9  10 11 12
        #  _________________
        # |        A        |
        #     _____
        #    | B   |
        #           ________
        #          |    C   |
        #              _______________________
        #             |     D                 |

        def test_durations_correct_with_sync_child_followed_by_concurrent_children
          segment_a, segment_b, segment_c, segment_d = nil, nil, nil, nil

          in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 1

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 2
            segment_b.finish


            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"
            advance_time 1

            segment_d = NewRelic::Agent::Tracer.start_segment(
              name: "metric d",
              parent: segment_a
            )

            advance_time 2
            segment_c.finish
            segment_a.finish

            advance_time 6
            segment_d.finish
          end

          assert_equal 6.0, segment_a.duration
          assert_equal 1.0, segment_a.exclusive_duration

          assert_equal 2.0, segment_b.duration
          assert_equal 2.0, segment_b.exclusive_duration

          assert_equal 3.0, segment_c.duration
          assert_equal 3.0, segment_c.exclusive_duration

          assert_equal 8.0, segment_d.duration
          assert_equal 8.0, segment_d.exclusive_duration
        end

        def test_transaction_detects_async_when_there_are_concurrent_children
          segment_a, segment_b, segment_c = nil, nil, nil

          in_transaction "test" do |txn|
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 2

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 1

            refute txn.async?

            segment_c = NewRelic::Agent::Tracer.start_segment(
              name: "metric c",
              parent: segment_a
            )

            assert txn.async?

            advance_time 1

            advance_time 1
            segment_b.finish

            advance_time 1
            segment_c.finish
            segment_a.finish
          end
        end

        def test_transaction_detects_async_when_child_ends_after_parent
          segment_a, segment_b, segment_c = nil, nil, nil

          in_transaction "test" do |txn|
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 1

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 2

            segment_b.finish

            refute txn.async?, "Expected transaction not to be asynchronous"

            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"

            advance_time 3
            segment_a.finish

            advance_time 4
            segment_c.finish

            assert txn.async?, "Expected transaction to be asynchronous"
          end
        end

        def test_transaction_records_exclusive_duration_millis_segment_param_when_transaction_async
          segment_a, segment_b, segment_c = nil, nil, nil

          in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 2

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 1

            segment_c = NewRelic::Agent::Tracer.start_segment(
              name: "metric c",
              parent: segment_a
            )

            advance_time 2
            segment_b.finish

            advance_time 1
            segment_c.finish
            segment_a.finish
          end

          assert_equal 2000.0, segment_a.params[:exclusive_duration_millis]
          assert_equal 3000.0, segment_b.params[:exclusive_duration_millis]
          assert_equal 3000.0, segment_c.params[:exclusive_duration_millis]
        end

        # B, C, D are children of A. C and D are running concurrently after B completes.
        # Here is a timeline to illustrate the situation:
        # 0  1  2  3  4  5  6  7
        #  ____________________
        # |        A           |
        #     _____
        #    | B   |
        #           ________
        #          |    C   |
        #              ________
        #             |     D  |

        def test_total_time_metrics_async_sync_children_non_web
          segment_a, segment_b, segment_c, segment_d = nil, nil, nil, nil

          transaction = in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 1

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 2
            segment_b.finish


            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"
            advance_time 1

            segment_d = NewRelic::Agent::Tracer.start_segment(
              name: "metric d",
              parent: segment_a
            )

            advance_time 2
            segment_c.finish
            advance_time 1

            segment_d.finish
            segment_a.finish
          end

          assert_equal 7.0, transaction.duration
          assert_equal 9.0, transaction.total_time

          assert_metrics_recorded(
            "OtherTransactionTotalTime" =>
              {
                :call_count => 1,
                :total_call_time => 9.0,
                :total_exclusive_time => 9.0
              },
            "OtherTransactionTotalTime/test" =>
              {
                :call_count => 1,
                :total_call_time => 9.0,
                :total_exclusive_time => 9.0
              }
          )
        end

        def test_total_time_metrics_async_sync_children_web
          segment_a, segment_b, segment_c, segment_d = nil, nil, nil, nil

          transaction = in_web_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 1

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 2
            segment_b.finish


            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"
            advance_time 1

            segment_d = NewRelic::Agent::Tracer.start_segment(
              name: "metric d",
              parent: segment_a
            )

            advance_time 2
            segment_c.finish
            advance_time 1

            segment_d.finish
            segment_a.finish
          end

          assert_equal 7.0, transaction.duration
          assert_equal 9.0, transaction.total_time

          assert_metrics_recorded(
            "WebTransactionTotalTime" =>
              {
                :call_count => 1,
                :total_call_time => 9.0,
                :total_exclusive_time => 9.0
              },
            "WebTransactionTotalTime/test" =>
              {
                :call_count => 1,
                :total_call_time => 9.0,
                :total_exclusive_time => 9.0
              }
          )
        end

        # B, C, D are children of A. C, D are running concurrently..
        # D ends after A finishes. Here is a timeline to illustrate the situation:
        # 0  1  2  3  4  5  6  7  8  9  10 11 12
        #  _________________
        # |        A        |
        #     _____
        #    | B   |
        #           ________
        #          |    C   |
        #              _______________________
        #             |     D                 |
        #
        #
        # Note that segment_d has components of exclusive time that need to be
        # removed from the "test" wrapper segment

        def test_times_accurate_when_child_finishes_after_parent
          segment_a, segment_b, segment_c, segment_d = nil, nil, nil, nil

          txn = in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 1

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"
            advance_time 2
            segment_b.finish


            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"
            advance_time 1

            segment_d = NewRelic::Agent::Tracer.start_segment(
              name: "metric d",
              parent: segment_a
            )

            advance_time 2
            segment_c.finish
            segment_a.finish

            advance_time 6
            segment_d.finish
          end

          assert_equal 12.0, txn.duration
          assert_equal 14.0, txn.total_time

          wrapper_segment = txn.segments.first

          assert_equal 12.0, wrapper_segment.duration
          assert_equal 0.0, wrapper_segment.exclusive_duration

          assert_equal 6.0, segment_a.duration
          assert_equal 1.0, segment_a.exclusive_duration

          assert_equal 2.0, segment_b.duration
          assert_equal 2.0, segment_b.exclusive_duration

          assert_equal 3.0, segment_c.duration
          assert_equal 3.0, segment_c.exclusive_duration

          assert_equal 8.0, segment_d.duration
          assert_equal 8.0, segment_d.exclusive_duration
        end

        # C, D, E are children of B. C, D, E are running concurrently.
        # E ends after B finishes. Here is a timeline to illustrate the situation:
        # 0  1  2  3  4  5  6  7  8  9  10 11 12
        #  _______________________
        # |        A              |
        #     ________________
        #    |       B        |
        #     ____
        #    | C  |
        #           ________
        #          |    D   |
        #              _______________________
        #             |     E                 |
        #
        #
        # Note that segment_e has components of exclusive time that need to be
        # removed from segment_a and the "test" wrapper segment

        def test_times_accurate_when_child_finishes_after_parent_more_nesting
          segment_a, segment_b, segment_c, segment_d, segment_e = nil, nil, nil, nil, nil

          txn = in_transaction "test" do
            segment_a = NewRelic::Agent::Tracer.start_segment name: "metric a"
            advance_time 1

            segment_b = NewRelic::Agent::Tracer.start_segment name: "metric b"

            segment_c = NewRelic::Agent::Tracer.start_segment name: "metric c"
            advance_time 2
            segment_c.finish


            segment_d = NewRelic::Agent::Tracer.start_segment name: "metric d"
            advance_time 1

            segment_e = NewRelic::Agent::Tracer.start_segment(
              name: "metric e",
              parent: segment_b
            )

            advance_time 2
            segment_d.finish

            advance_time 1
            segment_b.finish

            advance_time 1
            segment_a.finish

            advance_time 4
            segment_e.finish
          end

          assert_equal 12.0, txn.duration
          assert_equal 14.0, txn.total_time

          wrapper_segment = txn.segments.first

          assert_equal 12.0, wrapper_segment.duration
          assert_equal 0.0, wrapper_segment.exclusive_duration

          assert_equal 8.0, segment_a.duration
          assert_equal 1.0, segment_a.exclusive_duration

          assert_equal 6.0, segment_b.duration
          assert_equal 0.0, segment_b.exclusive_duration

          assert_equal 2.0, segment_c.duration
          assert_equal 2.0, segment_c.exclusive_duration

          assert_equal 3.0, segment_d.duration
          assert_equal 3.0, segment_d.duration

          assert_equal 8.0, segment_e.duration
          assert_equal 8.0, segment_e.exclusive_duration
        end
      end
    end
  end
end

