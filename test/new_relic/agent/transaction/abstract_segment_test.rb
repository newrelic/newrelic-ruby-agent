# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/abstract_segment'

module NewRelic
  module Agent
    class Transaction
      class AbstractSegmentTest < Minitest::Test
        class BasicSegment < AbstractSegment
          def record_metrics
            metric_cache.record_scoped_and_unscoped name, duration, exclusive_duration
            metric_cache.record_unscoped "Basic/all", duration, exclusive_duration
          end
        end

        def setup
          freeze_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_segment_is_nameable
          segment = BasicSegment.new  "Custom/basic/segment"
          assert_equal "Custom/basic/segment", segment.name
        end

        def test_segment_tracks_timing_information
          segment = BasicSegment.new "Custom/basic/segment"
          segment.start
          assert_equal Time.now, segment.start_time

          advance_time 1.0
          segment.finish

          assert_equal Time.now, segment.end_time
          assert_equal 1.0, segment.duration
          assert_equal 1.0, segment.exclusive_duration
        end

        def test_segment_records_metrics
          segment = BasicSegment.new "Custom/basic/segment"
          segment.start
          advance_time 1.0
          segment.finish

          assert_metrics_recorded ["Custom/basic/segment", "Basic/all"]
        end

        def test_segment_records_metrics_in_local_cache_if_part_of_transaction
          segment = BasicSegment.new "Custom/basic/segment"
          txn = in_transaction "test_transaction" do
            segment.transaction = txn
            segment.start
            advance_time 1.0
            segment.finish

            refute_metrics_recorded ["Custom/basic/segment", "Basic/all"]
          end

          #local metrics will be merged into global store at the end of the transction
          assert_metrics_recorded ["Custom/basic/segment", "Basic/all"]
        end

        # this preserves a strange case that is currently present in the agent where for some
        # segments we would like to create a TT node for the segment, but not record
        # metrics
        def test_segments_will_not_record_metrics_when_turned_off
          segment = BasicSegment.new "Custom/basic/segment"
          segment.record_metrics = false
          segment.start
          advance_time 1.0
          segment.finish

          refute_metrics_recorded ["Custom/basic/segment", "Basic/all"]
        end

        def test_segment_complete_callback_executes_when_segment_finished
          segment = BasicSegment.new "Custom/basic/segment"
          segment.expects(:segment_complete)
          segment.start
          advance_time 1.0
          segment.finish
        end
      end
    end
  end
end
