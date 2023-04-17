# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/abstract_segment'

module NewRelic
  module Agent
    class Transaction
      class AbstractSegmentTest < Minitest::Test
        class BasicSegment < AbstractSegment
          ALL_NAME = 'Basic/all'

          def record_metrics
            metric_cache.record_scoped_and_unscoped(name, duration, exclusive_duration)
            metric_cache.record_unscoped(ALL_NAME, duration, exclusive_duration)
          end
        end

        def basic_segment_name
          'Custom/basic/segment'
        end

        def basic_segment
          BasicSegment.new(basic_segment_name)
        end

        def setup
          nr_freeze_process_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_segment_notices_error
          with_segment do |segment|
            segment.notice_error(RuntimeError.new('notice me!'))

            assert segment.noticed_error, 'Expected an error to be noticed'
          end
        end

        def test_segment_keeps_most_recent_error
          with_segment do |segment|
            segment.notice_error(RuntimeError.new('notice me!'))
            segment.notice_error(RuntimeError.new('no, notice me!'))

            assert segment.noticed_error, 'Expected an error to be noticed'
            assert_equal 'no, notice me!', segment.noticed_error.message
          end
        end

        def test_segment_is_nameable
          assert_equal basic_segment_name, basic_segment.name
        end

        def test_segment_tracks_timing_information
          segment = nil

          in_transaction do |txn|
            segment = basic_segment
            txn.add_segment(segment)
            segment.start

            assert_equal Process.clock_gettime(Process::CLOCK_REALTIME), segment.start_time

            advance_process_time(1.0)
            segment.finish
          end

          assert_equal Process.clock_gettime(Process::CLOCK_REALTIME), segment.end_time
          assert_in_delta(1.0, segment.duration)
          assert_in_delta(1.0, segment.exclusive_duration)
        end

        def test_segment_records_metrics
          in_transaction do |txn|
            segment = basic_segment
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          assert_metrics_recorded [basic_segment_name, BasicSegment::ALL_NAME]
        end

        def test_segment_records_metrics_in_local_cache_if_part_of_transaction
          segment = basic_segment
          in_transaction('test_transaction') do |txn|
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish

            refute_metrics_recorded [basic_segment_name, BasicSegment::ALL_NAME]
          end

          # local metrics will be merged into global store at the end of the transaction
          assert_metrics_recorded [basic_segment_name, BasicSegment::ALL_NAME]
        end

        # this preserves a strange case that is currently present in the agent where for some
        # segments we would like to create a TT node for the segment, but not record
        # metrics
        def test_segments_will_not_record_metrics_when_turned_off
          in_transaction do |txn|
            segment = basic_segment
            txn.add_segment(segment)
            segment.record_metrics = false
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          refute_metrics_recorded [basic_segment_name, BasicSegment::ALL_NAME]
        end

        def test_segment_complete_callback_executes_when_segment_finished
          in_transaction do |txn|
            segment = basic_segment
            txn.add_segment(segment)
            segment.expects(:segment_complete)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end
        end

        def test_transaction_assigned_callback_executes_when_segment_added
          in_transaction do |txn|
            segment = basic_segment
            segment.expects(:transaction_assigned)
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end
        end

        def test_segment_records_metrics_on_finish
          in_transaction do |txn|
            segment = basic_segment
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.record_on_finish = true
            segment.finish

            assert_includes txn.metrics.instance_variable_get(:@scoped).keys, basic_segment_name
            assert_includes txn.metrics.instance_variable_get(:@unscoped).keys, BasicSegment::ALL_NAME
          end
        end

        def test_params_are_checkable_and_lazy_initializable
          segment = basic_segment

          refute segment.params?
          assert_nil segment.instance_variable_get(:@params)

          segment.params[:foo] = 'bar'

          assert_predicate segment, :params?
          assert_equal({foo: 'bar'}, segment.params)
        end

        def test_sets_start_time_from_constructor
          t = Process.clock_gettime(Process::CLOCK_REALTIME)
          segment = BasicSegment.new(nil, t)

          assert_equal t, segment.start_time
        end

        def test_sets_start_time_if_not_given_when_started
          t = Process.clock_gettime(Process::CLOCK_REALTIME)
          segment = BasicSegment.new
          segment.start

          assert_equal t, segment.start_time
        end

        def test_does_not_override_construction_start_time_when_started
          t = Process.clock_gettime(Process::CLOCK_REALTIME)
          segment = BasicSegment.new(nil, t)

          assert_equal t, segment.start_time
          advance_process_time(1)
          segment.start

          assert_equal t, segment.start_time
        end

        def test_parent_detects_concurrent_children
          in_transaction do |txn|
            segment_a = BasicSegment.new('segment_a')
            txn.add_segment(segment_a)
            segment_a.start
            segment_b = BasicSegment.new('segment_b')
            txn.add_segment(segment_b)
            segment_b.parent = segment_a
            segment_b.start
            segment_c = BasicSegment.new('segment_c')
            txn.add_segment(segment_c, segment_a)
            segment_c.start
            segment_b.finish
            segment_c.finish
            segment_a.finish

            assert_predicate segment_a, :concurrent_children?
            refute segment_b.concurrent_children?
            refute segment_c.concurrent_children?
          end
        end

        def test_root_segment_gets_transaction_name_attribute
          root_segment = nil
          transaction = nil

          with_segment do |segment, txn|
            root_segment = segment
            transaction = txn
          end

          # Once transaction finishes, root segment should have transaction_name that matches transaction name
          assert root_segment.transaction_name, 'Expected root segment to have a transaction_name'
          assert_equal transaction.best_name, root_segment.transaction_name
        end

        def clm_info
          {filepath: '/home/lhollyfeld/src/laseralignment/lib/models/mirror.rb',
           function: 'rotate',
           lineno: 1985,
           namespace: 'LaserAlignment::Mirror'}.freeze
        end

        def test_code_level_metrics_can_be_set
          with_segment do |segment|
            segment.code_information = clm_info

            assert_equal segment.instance_variable_get(:@code_filepath), clm_info[:filepath]
            assert_equal segment.instance_variable_get(:@code_function), clm_info[:function]
            assert_equal segment.instance_variable_get(:@code_lineno), clm_info[:lineno]
            assert_equal segment.instance_variable_get(:@code_namespace), clm_info[:namespace]
          end
        end

        def test_code_info_setting_short_circuits_if_filepath_is_absent
          with_segment do |segment|
            segment.code_information = clm_info.merge(filepath: nil)
            attributes = segment.code_attributes

            assert_equal NewRelic::EMPTY_HASH, attributes
          end
        end

        def test_code_level_metrics_attributes_are_exposed
          with_segment do |segment|
            segment.code_information = clm_info
            attributes = segment.code_attributes

            assert_equal attributes['code.filepath'], clm_info[:filepath]
            assert_equal attributes['code.function'], clm_info[:function]
            assert_equal attributes['code.lineno'], clm_info[:lineno]
            assert_equal attributes['code.namespace'], clm_info[:namespace]
          end
        end

        def test_code_level_metrics_attributes_are_empty_if_the_metrics_are_empty
          with_segment do |segment|
            assert_empty segment.code_attributes
          end
        end

        def test_code_level_metrics_are_all_or_nothing
          with_segment do |segment|
            segment.code_information = clm_info.reject { |key| key == :namespace }

            assert_empty(segment.code_attributes)
          end
        end

        def test_children_time_ranges_do_not_exist
          refute basic_segment.children_time_ranges?
        end

        def test_children_time_ranges_do_exist
          segment = basic_segment
          segment.instance_variable_set(:@children_timings, [[11.0, 38.0]])

          assert_predicate segment, :children_time_ranges?
        end

        def test_ranges_intersect_they_do
          assert basic_segment.send(:ranges_intersect?, 1..3, 2..4)
        end

        def test_ranges_intersect_they_do_not
          refute basic_segment.send(:ranges_intersect?, 1..3, 4..5)
        end

        # 1..3 and 2..4 overlap for a value of 1 (the distance between 2 and 3)
        def test_range_overlap_for_intersecting_ranges
          segment = basic_segment
          segment.instance_variable_set(:@start_time, 1.0)
          segment.instance_variable_set(:@end_time, 3.0)

          assert_in_delta(1.0, segment.send(:range_overlap, 2.0..4.0))
        end

        # 1..3 and 4..5 don't overlap at all, so the overlap amount is zero
        def test_range_overlap_for_non_intersecting_ranges
          segment = basic_segment
          segment.instance_variable_set(:@start_time, 1.0)
          segment.instance_variable_set(:@end_time, 3.0)

          assert_in_delta(0.0, segment.send(:range_overlap, 4.0..5.0))
        end
      end
    end
  end
end
