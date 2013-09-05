# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/thread_profile'
require 'new_relic/agent/threading/threaded_test_case'

if NewRelic::Agent::Commands::ThreadProfiler.is_supported?

  module NewRelic::Agent::Threading
    class ThreadProfileTest < ThreadedTestCase

      def setup
        super

        @single_trace = [
          "irb.rb:69:in `catch'",
          "irb.rb:69:in `start'",
          "irb:12:in `<main>'"
        ]

        @profile = ThreadProfile.new(create_agent_command)

        # Run the worker_loop for the thread profile based on two iterations
        # This takes time fussiness out of the equation and keeps the tests stable
        @profile.instance_variable_set(:@worker_loop, NewRelic::Agent::WorkerLoop.new(:limit => 2))
      end

      # Running Tests
      def test_profiler_collects_backtrace_from_every_thread
        FakeThread.list << FakeThread.new
        FakeThread.list << FakeThread.new

        @profile.run

        assert_equal 2, @profile.poll_count
        assert_equal 4, @profile.sample_count
      end

      def test_profiler_collects_into_request_bucket
        FakeThread.list << FakeThread.new(
          :bucket => :request,
          :backtrace => @single_trace)

          @profile.run

          assert_equal 1, @profile.traces[:request].size
      end

      def test_profiler_collects_into_background_bucket
        FakeThread.list << FakeThread.new(
          :bucket => :background,
          :backtrace => @single_trace)

          @profile.run

          assert_equal 1, @profile.traces[:background].size
      end

      def test_profiler_collects_into_other_bucket
        FakeThread.list << FakeThread.new(
          :bucket => :other,
          :backtrace => @single_trace)

          @profile.run

          assert_equal 1, @profile.traces[:other].size
      end

      def test_profiler_collects_into_agent_bucket
        FakeThread.list << FakeThread.new(
          :bucket => :agent,
          :backtrace => @single_trace)

          @profile.run

          assert_equal 1, @profile.traces[:agent].size
      end

      def test_profiler_ignores_agent_threads_when_told_to
        FakeThread.list << FakeThread.new(
          :bucket => :ignore,
          :backtrace => @single_trace)

          @profile.run

          @profile.traces.each do |key, trace|
            assert trace.empty?, "Trace :#{key} should have been empty"
          end
      end

      def test_profiler_tries_to_scrub_backtraces
        FakeThread.list << FakeThread.new(
          :bucket => :agent,
          :backtrace => @single_trace,
          :scrubbed_backtrace => @single_trace[0..0])

          @profile.run

          assert_equal [], @profile.traces[:agent].first.children
      end

      def test_profile_can_be_stopped
        # Can't easily stop in middle of processing since FakeThread's synchronous
        # Mark to bail immediately, then see we didn't record anything
        @profile.stop

        @profile.run

        assert_not_nil @profile.stop_time
        assert_equal true, @profile.finished?

        assert_equal 0, @profile.poll_count
        @profile.traces.each do |key, trace|
          assert_equal [], trace, "Trace for :#{key} should have been empty"
        end
      end

      def test_profiler_tracks_time
        @profile.run

        assert_not_nil @profile.start_time
        assert_not_nil @profile.stop_time
      end

      def test_finished
        assert !@profile.finished?

        @profile.run.join

        assert @profile.finished?
      end

      # Parsing and Aggregation Tests
      def test_parse_backtrace
        trace = [
          "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb:69:in `catch'",
          "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb:69:in `start'",
          "/Users/jclark/.rbenv/versions/1.9.3/bin/irb:12:in `<main>'"
        ]

        result = ThreadProfile.parse_backtrace(trace)
        assert_equal({ :method => 'catch',
                     :file => '/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb',
                     :line_no => 69 }, result[0])
        assert_equal({ :method => 'start',
                     :file => '/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb',
                     :line_no => 69 }, result[1])
        assert_equal({ :method => '<main>',
                     :file => '/Users/jclark/.rbenv/versions/1.9.3/bin/irb',
                     :line_no => 12 }, result[2])
      end

      def test_aggregate_empty_trace
        result = @profile.aggregate([])
        assert_nil result
      end

      def test_aggregate_nil_trace
        result = @profile.aggregate(nil)
        assert_nil result
      end

      def test_aggregate_builds_tree_from_first_trace
        result = @profile.aggregate(@single_trace)

        tree = BacktraceNode.new(@single_trace[-1])
        child = BacktraceNode.new(@single_trace[-2], tree)
        BacktraceNode.new(@single_trace[-3], child)

        assert_equal tree, result
      end

      def test_aggregate_builds_tree_from_overlapping_traces
        result = @profile.aggregate(@single_trace)
        result = @profile.aggregate(@single_trace, [result])

        tree = BacktraceNode.new(@single_trace[-1])
        tree.runnable_count += 1
        child = BacktraceNode.new(@single_trace[-2], tree)
        child.runnable_count += 1
        grand = BacktraceNode.new(@single_trace[-3], child)
        grand.runnable_count += 1

        assert_equal tree, result
      end

      def test_aggregate_builds_tree_from_diverging_traces
        other_trace = [
          "irb.rb:69:in `catch'",
          "chunky_bacon.rb:42:in `start'",
          "irb:12:in `<main>'"
        ]

        result = @profile.aggregate(@single_trace)
        result = @profile.aggregate(@single_trace, [result])

        tree = BacktraceNode.new(@single_trace[-1])
        tree.runnable_count += 1

        child = BacktraceNode.new(@single_trace[-2], tree)
        grand = BacktraceNode.new(@single_trace[-3], child)

        other_child = BacktraceNode.new(other_trace[-2], tree)
        other_grand = BacktraceNode.new(other_trace[-3], other_child)

        assert_equal tree, result
      end

      def test_prune_tree
        @profile.aggregate(@single_trace)

        t = @profile.prune!(1)

        assert_equal 0, @profile.traces[:request].first.children.size
      end

      def test_prune_keeps_highest_counts
        @profile.aggregate(@single_trace, @profile.traces[:request])
        @profile.aggregate(@single_trace, @profile.traces[:other])
        @profile.aggregate(@single_trace, @profile.traces[:other])

        @profile.prune!(1)

        assert_equal [], @profile.traces[:request]
        assert_equal 1, @profile.traces[:other].size
        assert_equal [], @profile.traces[:other][0].children
      end

      def test_prune_keeps_highest_count_then_depths
        @profile.aggregate(@single_trace, @profile.traces[:request])
        @profile.aggregate(@single_trace, @profile.traces[:other])

        @profile.prune!(2)

        assert_equal 1, @profile.traces[:request].size
        assert_equal 1, @profile.traces[:other].size
        assert_equal [], @profile.traces[:request][0].children
        assert_equal [], @profile.traces[:other][0].children
      end

      def build_well_known_trace
        trace = ["thread_profiler.py:1:in `<module>'"]
        10.times { @profile.aggregate(trace, @profile.traces[:other]) }

        trace = [
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:489:in `__bootstrap'",
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:512:in `__bootstrap_inner'",
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:480:in `run'",
          "thread_profiler.py:76:in `_profiler_loop'",
          "thread_profiler.py:103:in `_run_profiler'",
          "thread_profiler.py:165:in `collect_thread_stacks'"]
          10.times { @profile.aggregate(trace, @profile.traces[:agent]) }
      end

      WELL_KNOWN_TRACE_ENCODED = "eJy9klFPwjAUhf/LfW7WDQTUGBPUiYkGdAxelqXZRpGGrm1uS8xi/O924JQX\n9Un7dm77ndN7c19hlt7FCZxnWQZug7xYMYN6LSTHwDRA4KLWq53kl0CinEQh\nCUmW5zmBJH5axPPUk16MJ/E0/cGk0lLyyrGPS+uKamu943DQeX5HMtypz5In\nwv6vRCeZ1NoAGQ2PCDpvrOM1fRAlFtjQWyxq/qJxa+lj4zZaBeuuQpccrdDK\n0l4wolKU1OxftOoQLNTzIdL/EcjJafjnQYyVWjvrsDBMKNVOZBD1/jO27fPs\naBG+DoGr8fX9JJktpjftVry9A9unzGo=\n"

      def test_to_collector_array
        @profile.instance_variable_set(:@profile_id, "-1")
        @profile.instance_variable_set(:@start_time, 1350403938892.524)
        @profile.instance_variable_set(:@stop_time, 1350403939904.375)
        @profile.instance_variable_set(:@poll_count, 10)
        @profile.instance_variable_set(:@sample_count, 2)

        build_well_known_trace

        expected = [[
          -1,
          1350403938892.524,
          1350403939904.375,
          10,
          WELL_KNOWN_TRACE_ENCODED,
          2,
          0
        ]]

        marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
        assert_equal expected, @profile.to_collector_array(marshaller.default_encoder)
      end

      def test_to_collector_array_with_bad_values
        @profile.instance_variable_set(:@profile_id, "-1")
        @profile.instance_variable_set(:@start_time, "")
        @profile.instance_variable_set(:@stop_time, nil)
        @profile.instance_variable_set(:@poll_count, Rational(10, 1))
        @profile.instance_variable_set(:@sample_count, nil)

        build_well_known_trace

        expected = [[
          -1,
          0.0,
          0.0,
          10,
          WELL_KNOWN_TRACE_ENCODED,
          0,
          0
        ]]

        marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
        assert_equal expected, @profile.to_collector_array(marshaller.default_encoder)
      end
    end

  end
end
