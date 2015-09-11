# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/backtrace_service'
require 'new_relic/agent/threading/thread_profile'
require 'new_relic/agent/threading/threaded_test_case'

if NewRelic::Agent::Threading::BacktraceService.is_supported?

  module NewRelic::Agent::Threading
    class ThreadProfileTest < Minitest::Test
      include ThreadedTestCase

      def setup
        setup_fake_threads

        @single_trace = [
          "irb.rb:69:in `catch'",
          "irb.rb:69:in `start'",
          "irb:12:in `<main>'"
        ]

        @profile = ThreadProfile.new

        # Run the worker_loop for the thread profile based on two iterations
        # This takes time fussiness out of the equation and keeps the tests stable
        @profile.instance_variable_set(:@worker_loop, NewRelic::Agent::WorkerLoop.new(:limit => 2))
      end

      def teardown
        teardown_fake_threads
      end

      def target_for_shared_client_tests
        @profile
      end

      def test_prune_tree
        @profile.aggregate(@single_trace, :request, Thread.current)

        @profile.convert_N_trace_nodes_to_arrays(1)

        assert_equal 1, count_backtrace_nodes(@profile.traces[:request])
      end

      def test_prune_keeps_highest_counts
        @profile.aggregate(@single_trace, :request, Thread.current)
        @profile.aggregate(@single_trace, :other  , Thread.current)
        @profile.aggregate(@single_trace, :other  , Thread.current)

        @profile.convert_N_trace_nodes_to_arrays(1)

        assert_equal 0, count_backtrace_nodes(@profile.traces[:request])
        assert_equal 1, count_backtrace_nodes(@profile.traces[:other  ])
      end

      def test_prune_keeps_highest_count_then_depths
        @profile.aggregate(@single_trace, :request, Thread.current)
        @profile.aggregate(@single_trace, :other  , Thread.current)

        @profile.convert_N_trace_nodes_to_arrays(2)

        assert_equal 1, count_backtrace_nodes(@profile.traces[:request])
        assert_equal 1, count_backtrace_nodes(@profile.traces[:other  ])
      end

      def build_well_known_trace(args={})
        @profile = ThreadProfile.new(args)

        thread = stub
        trace = ["thread_profiler.py:1:in `<module>'"]
        10.times { @profile.aggregate(trace, :other, thread) }

        thread = stub
        trace = [
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:489:in `__bootstrap'",
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:512:in `__bootstrap_inner'",
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:480:in `run'",
          "thread_profiler.py:76:in `_profiler_loop'",
          "thread_profiler.py:103:in `_run_profiler'",
          "thread_profiler.py:165:in `collect_thread_stacks'"
        ]
        10.times { @profile.aggregate(trace, :agent, thread) }

        @profile.increment_poll_count
      end

      WELL_KNOWN_TRACE_ENCODED = "eJy9klFPwjAUhf/LfW7WDQTUGBPUiYkGdAxelqXZRpGGrm1uS8xi/O924JQX\n9Un7dm77ndN7c19hlt7FCZxnWQZug7xYMYN6LSTHwDRA4KLWq53kl0CinEQh\nCUmW5zmBJH5axPPUk16MJ/E0/cGk0lLyyrGPS+uKamu943DQeX5HMtypz5In\nwv6vRCeZ1NoAGQ2PCDpvrOM1fRAlFtjQWyxq/qJxa+lj4zZaBeuuQpccrdDK\n0l4wolKU1OxftOoQLNTzIdL/EcjJafjnQYyVWjvrsDBMKNVOZBD1/jO27fPs\naBG+DoGr8fX9JJktpjftVry9A9unzGo=\n"

      def test_to_collector_array
        build_well_known_trace('profile_id' => 333)
        @profile.stubs(:created_at).returns(1350403938892.524)
        @profile.finished_at = 1350403939904.375

        expected = [
          333,
          1350403938892.524,
          1350403939904.375,
          1,
          WELL_KNOWN_TRACE_ENCODED,
          2,
          0
        ]

        assert_equal expected, @profile.to_collector_array(encoder)
      end

      def test_to_collector_array_with_identity_encoder
        build_well_known_trace('profile_id' => 333)
        @profile.stubs(:created_at).returns(12)
        @profile.finished_at = 13

        expected = [
          333,
          12,
          13,
          1,
          @profile.generate_traces,
          2,
          0
        ]

        assert_equal expected, @profile.to_collector_array(NewRelic::Agent::NewRelicService::Encoders::Identity)
      end

      def test_to_collector_array_with_xray_session_id
        build_well_known_trace('profile_id' => -1, 'x_ray_id' => 4242)
        @profile.stubs(:created_at).returns(1350403938892.524)
        @profile.finished_at = 1350403939904.375

        expected = [
          -1,
          1350403938892.524,
          1350403939904.375,
          20,
          WELL_KNOWN_TRACE_ENCODED,
          2,
          0,
          4242
        ]

        assert_equal expected, @profile.to_collector_array(encoder)
      end

      def test_to_collector_array_with_bad_values
        build_well_known_trace(:profile_id => -1)
        @profile.stubs(:created_at).returns('')
        @profile.finished_at = nil
        @profile.instance_variable_set(:@poll_count, Rational(10, 1))
        @profile.instance_variable_set(:@backtrace_count, nil)
        @profile.instance_variable_set(:@unique_threads, nil)

        expected = [
          -1,
          0.0,
          0.0,
          10,
          WELL_KNOWN_TRACE_ENCODED,
          0,
          0
        ]

        assert_equal expected, @profile.to_collector_array(encoder)
      end

      def test_aggregate_should_increment_only_backtrace_count
        backtrace_count = @profile.backtrace_count
        failure_count = @profile.failure_count
        @profile.aggregate(@single_trace, :request, Thread.current)

        assert_equal backtrace_count + 1, @profile.backtrace_count
        assert_equal failure_count, @profile.failure_count
      end

      def test_aggregate_increments_only_the_failure_count_with_nil_backtrace
        backtrace_count = @profile.backtrace_count
        failure_count = @profile.failure_count
        @profile.aggregate(nil, :request, Thread.current)

        assert_equal backtrace_count, @profile.backtrace_count
        assert_equal failure_count + 1, @profile.failure_count
      end

      def test_aggregate_updates_created_at_timestamp
        expected = freeze_time
        @profile = ThreadProfile.new

        @profile.aggregate(@single_trace, :request, Thread.current)
        t0 = @profile.created_at

        advance_time(5.0)
        @profile.aggregate(@single_trace, :request, Thread.current)

        assert_equal expected, t0
        assert_equal expected, @profile.created_at
      end

      def test_aggregate_keeps_unique_thread_count
        thread0 = stub
        thread1 = stub

        @profile.aggregate(@single_trace, :request, thread0)
        @profile.aggregate(@single_trace, :request, thread0)
        @profile.aggregate(@single_trace, :request, thread1)

        assert_equal 2, @profile.unique_thread_count
      end

      SAMPLE_COUNT_POSITION = 3

      def test_sample_count_for_thread_profiling
        profile = ThreadProfile.new('x_ray_id' => nil)
        profile.increment_poll_count

        result = profile.to_collector_array(encoder)
        assert_equal 1, result[SAMPLE_COUNT_POSITION]
      end

      def test_sample_count_for_xrays
        profile = ThreadProfile.new('x_ray_id' => 123)
        profile.aggregate(@single_trace, :request, Thread.current)

        result = profile.to_collector_array(encoder)
        assert_equal 1, result[SAMPLE_COUNT_POSITION]
      end

      def test_empty
        profile = ThreadProfile.new
        assert profile.empty?
      end

      def test_not_empty
        profile = ThreadProfile.new
        profile.aggregate([], :request, Thread.current)
        assert_false profile.empty?
      end

      def encoder
        NewRelic::Agent::NewRelicService::JsonMarshaller.new.default_encoder
      end

      def count_backtrace_nodes(bt_node)
        trees = bt_node.as_array

        count = 0

        trees.each do |tree|
          count += rec_count_tree_nodes(tree)
        end

        count
      end

      def rec_count_tree_nodes(tree)
        count = 1 # 1 for this node

        children = tree[3]

        children.each do |child|
          count += rec_count_tree_nodes(child)
        end

        count
      end
    end

  end
end
