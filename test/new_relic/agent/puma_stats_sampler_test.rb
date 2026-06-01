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
          {last_status: {backlog: 1, running: 5, pool_capacity: 3, max_threads: 5}},
          {last_status: {backlog: 0, running: 4, pool_capacity: 4, max_threads: 5}}
        ]
      }.freeze

      SINGLE_STATS = {backlog: 2, running: 5, pool_capacity: 0, max_threads: 5}.freeze

      def setup
        NewRelic::Agent.drop_buffered_data
      end

      def test_aggregate_sums_clustered_worker_stats
        sampler = PumaStatsSampler.new(FakeLauncher.new(CLUSTERED_STATS))

        metrics = sampler.aggregate(CLUSTERED_STATS)

        assert_equal 2, metrics[:workers]
        assert_equal 1, metrics[:backlog]
        assert_equal 9, metrics[:running]
        assert_equal 7, metrics[:pool_capacity]
        assert_equal 10, metrics[:max_threads]
      end

      def test_aggregate_reads_single_mode_top_level_stats
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        metrics = sampler.aggregate(SINGLE_STATS)

        refute_includes metrics.keys, :workers
        assert_equal 2, metrics[:backlog]
        assert_equal 5, metrics[:running]
        assert_equal 0, metrics[:pool_capacity]
        assert_equal 5, metrics[:max_threads]
      end

      def test_sample_records_custom_puma_timeslice_metrics
        sampler = PumaStatsSampler.new(FakeLauncher.new(CLUSTERED_STATS))

        sampler.sample

        assert_metrics_recorded(
          'Puma/running' => {:total_call_time => 9},
          'Puma/backlog' => {:total_call_time => 1},
          'Puma/workers' => {:total_call_time => 2}
        )
      end

      def test_sample_parses_json_string_stats
        sampler = PumaStatsSampler.new(FakeLauncher.new(JSON.generate(SINGLE_STATS)))

        sampler.sample

        assert_metrics_recorded('Puma/running' => {:total_call_time => 5})
      end

      def test_sample_swallows_errors_and_logs
        raising_launcher = Object.new
        def raising_launcher.stats
          raise 'boom'
        end
        sampler = PumaStatsSampler.new(raising_launcher)

        # An error while sampling must never crash the Puma master thread.
        assert_nil sampler.sample
      end

      def test_should_sample_is_true_before_first_sample
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        assert_predicate sampler, :should_sample?
      end

      # The forced-reporting behavior is exercised directly rather than through
      # #start, whose sampling loop runs until #stop is called from another
      # thread (Puma's :state event handler) in production.
      def test_forces_master_reporting_thread_when_enabled
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        with_config(:'puma.start_reporting_thread_in_master' => true) do
          mock = Minitest::Mock.new
          mock.expect(:call, nil, [{force_reconnect: true}])
          NewRelic::Agent.stub(:after_fork, mock) do
            sampler.send(:ensure_master_is_reporting)
          end
          mock.verify
        end
      end

      def test_skips_master_reporting_thread_when_disabled
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        with_config(:'puma.start_reporting_thread_in_master' => false) do
          called = false
          NewRelic::Agent.stub(:after_fork, ->(*) { called = true }) do
            sampler.send(:ensure_master_is_reporting)
          end

          refute called, 'expected after_fork not to be called when master reporting is disabled'
        end
      end
    end
  end
end
