# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/continuous_profiling/stack_prof_sampler'

module NewRelic::Agent::ContinuousProfiling
  class StackProfSamplerTest < Minitest::Test
    def setup
      @sampler = StackProfSampler.new
    end

    def test_start_passes_mode_interval_and_raw_to_stackprof
      Object.stub_const(:StackProf, Module.new) do
        with_config(:'profiling.include' => 'cpu', :'profiling.sample_period' => 0.05) do
          StackProf.expects(:start).with(mode: :cpu, interval: 50_000, raw: true)

          @sampler.start
        end
      end
    end

    def test_start_passes_the_allocation_interval_for_object_mode
      Object.stub_const(:StackProf, Module.new) do
        with_config(:'profiling.include' => 'object', :'profiling.object_allocation_interval' => 1234) do
          StackProf.expects(:start).with(mode: :object, interval: 1234, raw: true)

          @sampler.start
        end
      end
    end

    def test_start_does_not_use_the_object_allocation_interval_for_cpu_mode
      Object.stub_const(:StackProf, Module.new) do
        with_config(:'profiling.include' => 'cpu', :'profiling.sample_period' => 0.05,
          :'profiling.object_allocation_interval' => 5) do
          StackProf.expects(:start).with(mode: :cpu, interval: 50_000, raw: true)

          @sampler.start
        end
      end
    end

    def test_stop_stops_stackprof_without_collecting_results
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:start).returns(true)
        StackProf.expects(:stop)
        StackProf.expects(:results).never
        @sampler.start

        @sampler.stop
      end
    end

    def test_stop_and_collect_stops_and_returns_results
      Object.stub_const(:StackProf, Module.new) do
        StackProf.expects(:stop)
        StackProf.expects(:results).returns({:samples => 1})
        StackProf.stubs(:start).returns(true)
        @sampler.start

        results = @sampler.stop_and_collect

        assert_equal 1, results[:samples]
      end
    end

    def test_stop_and_collect_includes_the_monotonic_to_realtime_clock_offset
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:start).returns(true)
        StackProf.stubs(:stop)
        StackProf.stubs(:results).returns({})

        Process.stub(:clock_gettime, ->(clock) { clock == Process::CLOCK_REALTIME ? 1_700_000_000.0 : 100.0 }) do
          @sampler.start
        end

        results = @sampler.stop_and_collect

        assert_in_delta(1_699_999_900.0, results[:clock_offset])
      end
    end

    def test_start_returns_false_when_stackprof_is_already_running
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:start).returns(false)

        refute @sampler.start
      end
    end

    def test_a_failed_start_does_not_advance_the_window_clocks
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:stop)
        StackProf.stubs(:results).returns({})
        realtime_values = [1_700_000_000.0, 1_700_000_005.0, 1_700_000_010.0]
        clock = ->(id) { id == Process::CLOCK_REALTIME ? realtime_values.shift : 100.0 }

        Process.stub(:clock_gettime, clock) do
          StackProf.stubs(:start).returns(false)
          @sampler.start

          StackProf.stubs(:start).returns(true)
          @sampler.start

          results = @sampler.stop_and_collect

          assert_in_delta(1_700_000_005.0, results[:window_start_realtime])
          assert_equal 5_000_000_000, results[:window_duration_nanos]
        end
      end
    end

    def test_stop_and_collect_returns_nil_when_stackprof_has_no_results
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:start).returns(true)
        StackProf.expects(:stop)
        StackProf.expects(:results).returns(nil)
        @sampler.start

        assert_nil @sampler.stop_and_collect
      end
    end

    def test_stop_and_collect_returns_nil_when_the_sampler_never_started
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:stop)
        StackProf.stubs(:results).returns({:samples => 1})

        assert_nil @sampler.stop_and_collect
      end
    end

    def test_stop_and_collect_returns_nil_when_the_window_was_already_collected
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:start).returns(true)
        StackProf.stubs(:stop)
        StackProf.stubs(:results).returns({:samples => 1})
        @sampler.start

        refute_nil @sampler.stop_and_collect
        assert_nil @sampler.stop_and_collect
      end
    end

    # A start only fails when a foreign profiler is running; its results are not ours to report,
    # nor to consume -- StackProf clears them on every read.
    def test_stop_and_collect_leaves_results_alone_after_a_failed_start
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:stop)
        StackProf.stubs(:results).returns({:samples => 1})
        StackProf.stubs(:start).returns(true)
        @sampler.start
        @sampler.stop_and_collect
        StackProf.stubs(:start).returns(false)
        @sampler.start
        StackProf.expects(:results).never

        assert_nil @sampler.stop_and_collect
      end
    end

    def test_stop_clears_the_window_so_a_later_collect_reports_nothing
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:start).returns(true)
        StackProf.stubs(:stop)
        StackProf.stubs(:results).returns({:samples => 1})
        @sampler.start
        @sampler.stop

        assert_nil @sampler.stop_and_collect
      end
    end

    def test_stop_and_collect_includes_the_window_start_and_duration
      Object.stub_const(:StackProf, Module.new) do
        StackProf.stubs(:start).returns(true)
        StackProf.stubs(:stop)
        StackProf.stubs(:results).returns({})
        realtime_values = [1_700_000_000.0, 1_700_000_010.0]

        Process.stub(:clock_gettime, ->(clock) { clock == Process::CLOCK_REALTIME ? realtime_values.shift : 100.0 }) do
          @sampler.start
          results = @sampler.stop_and_collect

          assert_in_delta(1_700_000_000.0, results[:window_start_realtime])
          assert_equal 10_000_000_000, results[:window_duration_nanos]
        end
      end
    end
  end
end
