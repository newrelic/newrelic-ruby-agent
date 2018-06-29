# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction/segment'

module NewRelic
  module Agent
    class Transaction
      class SegmentTest < Minitest::Test
        def setup
          nr_freeze_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_assigns_unscoped_metrics
          segment = Segment.new  "Custom/simple/segment", "Segment/all"
          assert_equal "Custom/simple/segment", segment.name
          assert_equal "Segment/all", segment.unscoped_metrics
        end

        def test_assigns_unscoped_metrics_as_array
          segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Other/all"]
          assert_equal "Custom/simple/segment", segment.name
          assert_equal ["Segment/all", "Other/all"], segment.unscoped_metrics
        end

        def test_segment_does_not_record_metrics_outside_of_txn
          segment = Segment.new  "Custom/simple/segment", "Segment/all"
          segment.start
          advance_time 1.0
          segment.finish

          refute_metrics_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_does_not_record_metrics_outside_of_txn
          segment = Segment.new  "Custom/simple/segment", "Segment/all"
          segment.start
          advance_time 1.0
          segment.finish

          assert_metrics_not_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_records_metrics
          in_transaction "test" do |txn|
            segment = Segment.new  "Custom/simple/segment", "Segment/all"
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          assert_metrics_recorded_exclusive [
            "test",
            ["Custom/simple/segment", "test"],
            "Custom/simple/segment",
            "Segment/all",
            "Supportability/API/drop_buffered_data",
            "OtherTransactionTotalTime",
            "OtherTransactionTotalTime/test"
          ]
        end

        def test_segment_records_metrics_when_given_as_array
          in_transaction do |txn|
            segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Other/all"]
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all", "Other/all"]
        end

        def test_segment_can_disable_scoped_metric_recording
          in_transaction('test') do |txn|
            segment = Segment.new  "Custom/simple/segment", "Segment/all"
            segment.record_scoped_metric = false
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          assert_metrics_recorded_exclusive [
            "test",
            "Custom/simple/segment",
            "Segment/all",
            "Supportability/API/drop_buffered_data",
            "OtherTransactionTotalTime",
            "OtherTransactionTotalTime/test"
          ]
        end

        def test_segment_can_disable_scoped_metric_recording_with_unscoped_as_frozen_array
          in_transaction('test') do |txn|
            segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Segment/allOther"].freeze
            segment.record_scoped_metric = false
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          assert_metrics_recorded_exclusive [
            "test",
            "Custom/simple/segment",
            "Segment/all",
            "Segment/allOther",
            "Supportability/API/drop_buffered_data",
            "OtherTransactionTotalTime",
            "OtherTransactionTotalTime/test"
          ]
        end

        def test_non_sampled_segment_does_not_record_span_event
          in_transaction('wat') do |txn|
            txn.sampled = false

            segment = Segment.new 'Ummm'
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          assert_empty last_span_events
        end

        def test_sampled_segment_records_span_event
          trace_id  = nil
          txn_guid  = nil
          sampled   = nil
          priority  = nil
          timestamp = nil

          in_transaction('wat') do |txn|
            txn.sampled = true

            segment = Segment.new 'Ummm'
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish

            timestamp = Integer(segment.start_time.to_f * 1000.0)

            trace_id = txn.trace_id
            txn_guid = txn.guid
            sampled  = txn.sampled?
            priority = txn.priority
          end

          last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          assert_equal 2, last_span_events.size
          custom_span_event = last_span_events[0][0]
          root_span_event   = last_span_events[1][0]
          root_guid         = root_span_event['guid']

          assert_equal 'Span',    custom_span_event.fetch('type')
          assert_equal trace_id,  custom_span_event.fetch('traceId')
          refute_nil              custom_span_event.fetch('guid')
          assert_equal root_guid, custom_span_event.fetch('parentId')
          assert_equal txn_guid,  custom_span_event.fetch('transactionId')
          assert_equal sampled,   custom_span_event.fetch('sampled')
          assert_equal priority,  custom_span_event.fetch('priority')
          assert_equal timestamp, custom_span_event.fetch('timestamp')
          assert_equal 1.0,       custom_span_event.fetch('duration')
          assert_equal 'Ummm',    custom_span_event.fetch('name')
          assert_equal 'generic', custom_span_event.fetch('category')
        end

        def test_span_event_parenting
          txn_segment = nil
          segment_a = nil
          segment_b = nil
          txn = in_transaction('test_txn') do |t|
            t.sampled = true
            txn_segment = t.initial_segment
            segment_a = NewRelic::Agent::Transaction.start_segment(name: 'segment_a')
            segment_b = NewRelic::Agent::Transaction.start_segment(name: 'segment_b')
            segment_b.finish
            segment_a.finish
          end

          last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

          txn_segment_event, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "test_txn" }

          assert_equal txn.guid, txn_segment_event["transactionId"]
          assert_nil   txn_segment_event["parentId"]

          segment_event_a, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "segment_a" }

          assert_equal txn.guid, segment_event_a["transactionId"]
          assert_equal txn_segment.guid, segment_event_a["parentId"]

          segment_event_b, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "segment_b" }

          assert_equal txn.guid, segment_event_b["transactionId"]
          assert_equal segment_a.guid, segment_event_b["parentId"]
        end

        def test_sets_start_time_from_constructor
          t = Time.now
          segment = Segment.new nil, nil, t
          assert_equal t, segment.start_time
        end
      end
    end
  end
end
