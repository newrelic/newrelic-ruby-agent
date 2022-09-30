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
          assert_equal 1.0, segment.duration
          assert_equal 1.0, segment.exclusive_duration
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
          assert segment.params?
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

            assert segment_a.concurrent_children?
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
            assert_equal(segment.code_attributes, {})
          end
        end

        def test_code_level_metrics_are_all_or_nothing
          with_segment do |segment|
            segment.code_information = clm_info.reject { |key| key == :namespace }
            assert_equal(segment.code_attributes, {})
          end
        end

        # BEGIN children time ranges
        def test_children_time_ranges_do_not_exist
          refute basic_segment.children_time_ranges?
        end

        def test_children_time_ranges_do_exist
          segment = basic_segment
          segment.instance_variable_set(:@children_timings, [[11.0, 38.0]])
          assert segment.children_time_ranges?
        end

        def test_during_recording_timings_become_ranges
          # this is an array of [start_time, finish_time] arrays
          input = [[1, 3], [2, 5], [6, 10], [11, 15], [12, 13], [20, 30], [25, 35], [40, 50]]
          # after the input arrays are merged when overlapping and converted to
          # ranges, the following result is expected.
          # NOTE: [1,3] and [2,5] overlap to become 1..5
          #       [11,15] and [12,13] overlap and [12,13] is effectively discarded
          #       [20,30] and [25,35] overlap and become 20..35
          #       [6,10] and [40,50] don't overlap with any other pair
          expected = [1..5, 6..10, 11..15, 20..35, 40..50]
          segment = basic_segment
          segment.instance_variable_set(:@children_timings, input)
          result = segment.send(:children_time_ranges)
          assert_equal expected, result
        end

        def overlapping_pairs
          [[11, 30], [24, 38]]
        end

        def non_overlapping_pairs
          [[1, 3], [5, 8]]
        end

        def test_merging_of_timings
          assert_equal [11, 38], basic_segment.send(:merge_timings, overlapping_pairs.first, overlapping_pairs.last)
        end

        def test_merging_of_timings_with_params_in_reverse
          assert_equal [11, 38], basic_segment.send(:merge_timings, overlapping_pairs.last, overlapping_pairs.first)
        end

        def test_pairs_are_seen_as_overlapping
          assert basic_segment.send(:timings_overlap?, overlapping_pairs.first, overlapping_pairs.last)
        end

        def test_pairs_are_seen_as_non_overlapping
          refute basic_segment.send(:timings_overlap?, non_overlapping_pairs.first, non_overlapping_pairs.last)
        end
        # END children time ranges
      end
    end
  end
end
