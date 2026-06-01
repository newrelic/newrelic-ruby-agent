# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/puma_stats_sampler'

module NewRelic
  module Agent
    class PumaStatsSamplerTest < Minitest::Test
      # Minimal stand-in for Puma::Launcher exposing only #stats.
      FakeLauncher = Struct.new(:stats)

      CLUSTERED_STATS = {
        workers: 2,
        worker_status: [
          {last_status: {backlog: 1, running: 5, pool_capacity: 3, max_threads: 5, requests_count: 100}},
          {last_status: {backlog: 0, running: 4, pool_capacity: 4, max_threads: 5, requests_count: 150}}
        ]
      }.freeze

      SINGLE_STATS = {backlog: 2, running: 5, pool_capacity: 0, max_threads: 5, requests_count: 42}.freeze

      def setup
        NewRelic::Agent.drop_buffered_data
      end

      # --- aggregation -------------------------------------------------------

      def test_aggregate_sums_clustered_worker_stats
        sampler = PumaStatsSampler.new(FakeLauncher.new(CLUSTERED_STATS))

        metrics = sampler.send(:aggregate, CLUSTERED_STATS)

        assert_equal 2, metrics[:workers]
        assert_equal 1, metrics[:backlog]
        assert_equal 9, metrics[:running]
        assert_equal 7, metrics[:pool_capacity]
        assert_equal 10, metrics[:max_threads]
        assert_equal 250, metrics[:requests_count]
      end

      def test_aggregate_reads_single_mode_top_level_stats
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        metrics = sampler.send(:aggregate, SINGLE_STATS)

        refute_includes metrics.keys, :workers
        assert_equal 2, metrics[:backlog]
        assert_equal 5, metrics[:running]
        assert_equal 0, metrics[:pool_capacity]
        assert_equal 5, metrics[:max_threads]
        assert_equal 42, metrics[:requests_count]
      end

      def test_aggregate_tolerates_missing_or_partial_last_status
        stats = {workers: 2, worker_status: [{}, {last_status: {running: 3}}]}
        sampler = PumaStatsSampler.new(FakeLauncher.new(stats))

        metrics = sampler.send(:aggregate, stats)

        assert_equal 2, metrics[:workers]
        assert_equal 3, metrics[:running]
        assert_equal 0, metrics[:backlog] # absent keys default to 0, never nil
      end

      # --- metric recording --------------------------------------------------

      def test_sample_records_puma_timeslice_metrics
        sampler = PumaStatsSampler.new(FakeLauncher.new(CLUSTERED_STATS))

        sampler.send(:sample)

        assert_metrics_recorded(
          'Puma/running' => {:total_call_time => 9},
          'Puma/backlog' => {:total_call_time => 1},
          'Puma/requests_count' => {:total_call_time => 250},
          'Puma/workers' => {:total_call_time => 2},
          # pool_capacity (3 + 4) is reported under the clearer name
          'Puma/spare_thread_capacity' => {:total_call_time => 7}
        )
        assert_metrics_not_recorded('Puma/pool_capacity')
      end

      def test_sample_parses_json_string_stats
        sampler = PumaStatsSampler.new(FakeLauncher.new(JSON.generate(SINGLE_STATS)))

        sampler.send(:sample)

        assert_metrics_recorded('Puma/running' => {:total_call_time => 5})
      end

      def test_sample_does_not_raise_on_stats_error_and_counts_failures
        raising_launcher = Object.new
        def raising_launcher.stats
          raise 'boom'
        end
        sampler = PumaStatsSampler.new(raising_launcher)

        # An error while sampling must never crash the Puma master thread.
        sampler.send(:sample)
        sampler.send(:sample)

        assert_equal 2, sampler.instance_variable_get(:@consecutive_failures)
      end

      def test_sample_resets_failure_count_after_success
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))
        sampler.instance_variable_set(:@consecutive_failures, 5)

        sampler.send(:sample)

        assert_equal 0, sampler.instance_variable_get(:@consecutive_failures)
      end

      # --- sample rate config ------------------------------------------------

      def test_resolve_sample_rate_uses_config_value
        with_config(:'puma.sample_rate' => 30) do
          assert_equal 30, PumaStatsSampler.new(FakeLauncher.new(nil)).send(:resolve_sample_rate)
        end
      end

      def test_resolve_sample_rate_falls_back_when_non_positive
        with_config(:'puma.sample_rate' => 0) do
          assert_equal PumaStatsSampler::DEFAULT_SAMPLE_RATE,
            PumaStatsSampler.new(FakeLauncher.new(nil)).send(:resolve_sample_rate)
        end
      end

      def test_failure_backoff_grows_and_caps
        with_config(:'puma.sample_rate' => 10) do
          sampler = PumaStatsSampler.new(FakeLauncher.new(nil))

          assert_equal 10, sampler.send(:next_wait_interval) # no failures
          sampler.instance_variable_set(:@consecutive_failures, 1)

          assert_equal 10, sampler.send(:next_wait_interval) # 2**0 * 10
          sampler.instance_variable_set(:@consecutive_failures, 3)

          assert_equal 40, sampler.send(:next_wait_interval) # 2**2 * 10
          sampler.instance_variable_set(:@consecutive_failures, 50)

          assert_equal 80, sampler.send(:next_wait_interval) # capped at 2**3 * 10
        end
      end

      # --- start / stop loop -------------------------------------------------

      def test_start_samples_until_stopped
        sampled = Queue.new
        launcher = Object.new
        launcher.define_singleton_method(:stats) do
          sampled << :tick
          SINGLE_STATS
        end

        with_config(:'puma.start_reporting_thread_in_master' => false) do
          sampler = PumaStatsSampler.new(launcher)
          thread = Thread.new { sampler.start }

          sampled.pop # deterministically wait for the first sample
          sampler.stop

          assert thread.join(5), 'expected the sampling loop to exit promptly after #stop'
          assert_metrics_recorded('Puma/running' => {:total_call_time => 5})
        end
      end

      def test_stop_before_start_prevents_sampling
        launcher = FakeLauncher.new(SINGLE_STATS)

        with_config(:'puma.start_reporting_thread_in_master' => false) do
          sampler = PumaStatsSampler.new(launcher)
          sampler.stop

          assert thread_completes? { sampler.start }
          assert_metrics_not_recorded('Puma/running')
        end
      end

      # --- master reporting thread -------------------------------------------

      # The forced-reporting behavior is exercised directly rather than through
      # #start, whose sampling loop runs until #stop is called from another
      # thread (Puma's :state event handler) in production.
      def test_forces_master_reporting_thread_when_enabled
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        with_config(:'puma.start_reporting_thread_in_master' => true) do
          mock = Minitest::Mock.new
          mock.expect(:call, nil, [{force_reconnect: true}])

          NewRelic::Agent.stub(:after_fork, mock) do
            assert sampler.send(:ensure_master_is_reporting)
          end
          mock.verify
        end
      end

      def test_skips_master_reporting_thread_when_disabled
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        with_config(:'puma.start_reporting_thread_in_master' => false) do
          called = false

          NewRelic::Agent.stub(:after_fork, ->(*) { called = true }) do
            assert sampler.send(:ensure_master_is_reporting)
          end

          refute called, 'expected after_fork not to be called when master reporting is disabled'
        end
      end

      def test_ensure_master_is_reporting_returns_false_on_failure
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        with_config(:'puma.start_reporting_thread_in_master' => true) do
          NewRelic::Agent.stub(:after_fork, ->(*) { raise 'connect failed' }) do
            refute sampler.send(:ensure_master_is_reporting),
              'a failed reporting-thread start should return false so sampling is skipped'
          end
        end
      end

      private

      def thread_completes?(timeout = 5, &block)
        Thread.new(&block).join(timeout)
      end
    end
  end
end
