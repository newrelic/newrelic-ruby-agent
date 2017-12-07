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
          frozen_time
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

        def test_sets_start_time_from_constructor
          t = Time.now
          segment = Segment.new nil, nil, t
          assert_equal t, segment.start_time
        end
      end
    end
  end
end
