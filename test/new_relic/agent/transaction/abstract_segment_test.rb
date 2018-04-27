# frozen_string_literal: true

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
          nr_freeze_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_segment_is_nameable
          segment = BasicSegment.new  "Custom/basic/segment"
          assert_equal "Custom/basic/segment", segment.name
        end

        def test_segment_tracks_timing_information
          segment = nil

          in_transaction do |txn|
            segment = BasicSegment.new "Custom/basic/segment"
            txn.add_segment segment
            segment.start
            assert_equal Time.now, segment.start_time

            advance_time 1.0
            segment.finish
          end

          assert_equal Time.now, segment.end_time
          assert_equal 1.0, segment.duration
          assert_equal 1.0, segment.exclusive_duration
        end

        def test_segment_records_metrics
          in_transaction do |txn|
            segment = BasicSegment.new "Custom/basic/segment"
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          assert_metrics_recorded ["Custom/basic/segment", "Basic/all"]
        end

        def test_segment_records_metrics_in_local_cache_if_part_of_transaction
          segment = BasicSegment.new "Custom/basic/segment"
          in_transaction "test_transaction" do |txn|
            txn.add_segment segment
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
          in_transaction do |txn|
            segment = BasicSegment.new "Custom/basic/segment"
            txn.add_segment segment
            segment.record_metrics = false
            segment.start
            advance_time 1.0
            segment.finish
          end

          refute_metrics_recorded ["Custom/basic/segment", "Basic/all"]
        end

        def test_segment_complete_callback_executes_when_segment_finished
          in_transaction do |txn|
            segment = BasicSegment.new "Custom/basic/segment"
            txn.add_segment segment
            segment.expects(:segment_complete)
            segment.start
            advance_time 1.0
            segment.finish
          end
        end

        def test_segment_records_metrics_on_finish
          in_transaction do |txn|
            segment = BasicSegment.new "Custom/basic/segment"
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.record_on_finish = true
            segment.finish
            assert_includes txn.metrics.instance_variable_get(:@scoped).keys, 'Custom/basic/segment'
            assert_includes txn.metrics.instance_variable_get(:@unscoped).keys, 'Basic/all'
          end
        end

        def test_params_are_checkable_and_lazy_initializable
          segment = BasicSegment.new "Custom/basic/segment"
          refute segment.params?
          assert_nil segment.instance_variable_get :@params

          segment.params[:foo] = "bar"
          assert segment.params?
          assert_equal({foo: "bar"}, segment.params)
        end

        def test_sets_start_time_from_constructor
          t = Time.now
          segment = BasicSegment.new nil, t
          assert_equal t, segment.start_time
        end

        def test_sets_start_time_if_not_given_when_started
          t = Time.now
          segment = BasicSegment.new
          segment.start
          assert_equal t, segment.start_time
        end

        def test_does_not_override_construction_start_time_when_started
          t = Time.now
          segment = BasicSegment.new nil, t
          assert_equal t, segment.start_time
          advance_time 1
          segment.start
          assert_equal t, segment.start_time
        end

        def test_parent_detects_concurrent_children
          in_transaction do |txn|
            segment_a = BasicSegment.new "segment_a"
            txn.add_segment segment_a
            segment_a.start
            segment_b = BasicSegment.new "segment_b"
            txn.add_segment segment_b
            segment_b.parent = segment_a
            segment_b.start
            segment_c = BasicSegment.new "segment_c"
            txn.add_segment segment_c, segment_a
            segment_c.start
            segment_b.finish
            segment_c.finish
            segment_a.finish

            assert segment_a.concurrent_children?
            refute segment_b.concurrent_children?
            refute segment_c.concurrent_children?
          end
        end
      end
    end
  end
end
