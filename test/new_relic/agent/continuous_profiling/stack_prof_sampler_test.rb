# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/continuous_profiling/stack_prof_sampler'

module NewRelic::Agent::ContinuousProfiling
  class StackProfSamplerTest < Minitest::Test
    def setup
      @sampler = StackProfSampler.new
      stub_stackprof_gem
    end

    def teardown
      remove_stackprof_gem
    end

    def test_start_passes_mode_interval_and_raw_to_stackprof
      with_config(:'continuous_profiler.mode' => 'cpu', :'continuous_profiler.sample_period' => 0.05) do
        StackProf.expects(:start).with(mode: :cpu, interval: 50_000, raw: true)

        @sampler.start
      end
    end

    def test_start_records_a_mode_supportability_metric
      StackProf.stubs(:start)

      with_config(:'continuous_profiler.mode' => 'object') do
        @sampler.start

        assert_metrics_recorded('Supportability/Ruby/Profiling/Mode/object')
      end
    end

    def test_stop_and_collect_stops_and_returns_results
      StackProf.expects(:stop)
      StackProf.expects(:results).returns({:samples => 1})

      assert_equal({:samples => 1}, @sampler.stop_and_collect)
    end

    private

    def stub_stackprof_gem
      Object.const_set(:StackProf, Module.new) unless defined?(StackProf)
    end

    def remove_stackprof_gem
      Object.send(:remove_const, :StackProf) if defined?(StackProf)
    end
  end
end
