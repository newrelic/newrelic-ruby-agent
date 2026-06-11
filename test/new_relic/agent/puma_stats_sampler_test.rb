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

      def test_aggregate_tolerates_empty_worker_status_during_clustered_boot
        # A clustered master observed before its workers spawn briefly
        # produces +worker_status: []+. That is a recognized shape (not
        # UnrecognizedStatsError) and yields just the configured worker
        # count with zeros for the per-worker gauges. Locks in the
        # deliberate boot carve-out so a future "tighten the truthy check"
        # refactor (e.g. +worker_status&.any?+) regresses loudly.
        stats = {workers: 2, worker_status: []}
        sampler = PumaStatsSampler.new(FakeLauncher.new(stats))

        metrics = sampler.send(:aggregate, stats)

        assert_equal 2, metrics[:workers]
        assert_equal 0, metrics[:running]
        assert_equal 0, metrics[:backlog]
      end

      def test_aggregate_tolerates_pre_server_single_mode_stats_during_boot
        # A single-mode runner sampled before its Puma::Server exists reports
        # only runner metadata (+:started_at+, +:versions+). The sampler is
        # installed while Puma is still binding (before start_server), so the
        # first sample can land in that window; it must be a recognized shape
        # (not UnrecognizedStatsError) with nothing to record. Locks in the
        # boot carve-out alongside the clustered empty-worker_status one.
        stats = {started_at: '2026-01-01T00:00:00Z', versions: {puma: '8.0.2'}}
        sampler = PumaStatsSampler.new(FakeLauncher.new(stats))

        metrics = sampler.send(:aggregate, stats)

        assert_empty metrics
      end

      def test_aggregate_raises_on_unrecognized_stats_shape
        # A future Puma release renaming the keys, or another plugin
        # overriding launcher.stats, must not silently produce zero metrics.
        # Each case below guards against a different "helpful refactor"
        # that would silently regress the fix: widening the truthy guard,
        # an early-return on stats.empty?, or treating :workers alone as a
        # cluster signal.
        sampler = PumaStatsSampler.new(FakeLauncher.new(nil))

        [
          {},
          {some_other_key: 'foo'},
          {workers: 5}, # :workers is not in WORKER_STAT_KEYS; must still raise
          # Runner metadata mixed with unrecognized keys must still raise --
          # the pre-server boot carve-out is strict (metadata keys only), so
          # renamed per-worker keys cannot ride in under :started_at.
          {started_at: '2026-01-01T00:00:00Z', queue_depth: 3}
        ].each do |shape|
          assert_raises(NewRelic::Agent::PumaStatsSampler::UnrecognizedStatsError,
            "expected aggregate to raise on shape: #{shape.inspect}") do
            sampler.send(:aggregate, shape)
          end
        end
      end

      def test_sample_routes_unrecognized_stats_through_failure_path
        # End-to-end: an unrecognized stats hash must engage the throttled
        # sample-failure path (counter increments, log line emitted, NO
        # metrics recorded, backoff extends) so operators see a clear
        # signal instead of silent zero metrics.
        launcher = Object.new
        launcher.define_singleton_method(:stats) { {some_other_key: 'foo'} }
        sampler = PumaStatsSampler.new(launcher)

        logger = StubLogger.new
        NewRelic::Agent.stub(:logger, logger) do
          2.times { sampler.send(:sample) }
        end

        assert_equal 2, sampler.instance_variable_get(:@consecutive_failures)
        assert(logger.errors.any? { |m| m.include?('Error sampling Puma stats') },
          "expected sample-failure log for unrecognized stats shape; got: #{logger.errors.inspect}")
        # No Puma/* metrics should be recorded — that is the actual
        # user-visible bug ("silent zero-metric recording") this guards.
        assert_metrics_not_recorded(%w[Puma/backlog Puma/running Puma/spare_thread_capacity Puma/max_threads Puma/requests_count Puma/workers])
        # Backoff engages: at 2 failures the next wait is 2x the sample rate
        # (exponent = consecutive_failures - 1 = 1).
        assert_equal sampler.instance_variable_get(:@sample_rate) * 2,
          sampler.send(:next_wait_interval)
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
          # pool_capacity (3 + 4) is reported under a name that conveys what
          # the value means: additional requests the pool can accept right
          # now (idle threads + unspawned threads still allowed up to max).
          'Puma/spare_thread_capacity' => {:total_call_time => 7}
        )
        assert_metrics_not_recorded('Puma/pool_capacity')
      end

      def test_sample_parses_json_string_stats
        sampler = PumaStatsSampler.new(FakeLauncher.new(JSON.generate(SINGLE_STATS)))

        sampler.send(:sample)

        assert_metrics_recorded('Puma/running' => {:total_call_time => 5})
      end

      def test_sample_parses_clustered_json_string_stats
        # Older Puma versions return launcher.stats as a JSON string even in
        # clustered mode. Covers the symbolize_names path against the
        # nested :worker_status shape, not just single-mode top-level keys.
        sampler = PumaStatsSampler.new(FakeLauncher.new(JSON.generate(CLUSTERED_STATS)))

        sampler.send(:sample)

        assert_metrics_recorded(
          'Puma/workers' => {:total_call_time => 2},
          'Puma/running' => {:total_call_time => 9},
          'Puma/spare_thread_capacity' => {:total_call_time => 7}
        )
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

      def test_sample_resets_report_failure_count_after_success
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))
        sampler.instance_variable_set(:@consecutive_report_failures, 5)

        sampler.send(:sample)

        assert_equal 0, sampler.instance_variable_get(:@consecutive_report_failures),
          'a successful record_metric pass must clear the report-failure counter'
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

      def test_stop_is_idempotent
        # The plugin registers four launcher-level handlers (Puma 6.x and
        # 7+ event names) so overlapping shutdown events can call #stop
        # more than once. Confirm repeated invocation is safe -- no
        # exceptions, no state regression.
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        3.times { sampler.stop }

        assert sampler.instance_variable_get(:@stopped)
        refute sampler.instance_variable_get(:@running)
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

      # --- start-loop exception handling ------------------------------------

      def test_start_loop_rescue_logs_and_exits_on_standarderror
        # Verifies the wrapper around #start's loop body. Without it Puma's
        # bare Thread.new in fire_background would let any escape from the
        # sampling loop silently kill the sampler thread.
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))
        sampler.define_singleton_method(:sample) { raise 'unexpected loop blow-up' }

        logger = StubLogger.new
        with_config(:'puma.start_reporting_thread_in_master' => false) do
          NewRelic::Agent.stub(:logger, logger) do
            sampler.start # must not raise; rescue logs and returns
          end
        end

        assert(logger.errors.any? { |m| m.include?('exited with error') },
          "expected the StandardError rescue to log; got: #{logger.errors.inspect}")
        refute sampler.instance_variable_get(:@running),
          '@running must be reset on the rescue path so subsequent #stop is consistent'
      end

      def test_start_loop_logs_and_re_raises_on_exception_subclass
        # Verifies the second rescue clause: a non-StandardError (the kind a
        # process signal becomes) is logged and re-raised so interrupts still
        # propagate to Puma instead of getting silently swallowed.
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))
        sentinel = Class.new(Exception)
        sampler.define_singleton_method(:sample) { raise sentinel, 'simulated interrupt' }

        logger = StubLogger.new
        raised = nil
        with_config(:'puma.start_reporting_thread_in_master' => false) do
          NewRelic::Agent.stub(:logger, logger) do
            sampler.start
          rescue sentinel => e
            raised = e
          end
        end

        refute_nil raised, 'Exception subclass must be re-raised, not swallowed'
        assert(logger.errors.any? { |m| m.include?('Re-raising in case of interrupt') },
          "expected the Exception rescue log line; got: #{logger.errors.inspect}")
      end

      # --- failure logging cadence ------------------------------------------

      def test_log_sample_failure_logs_first_and_every_nth
        sampler = PumaStatsSampler.new(FakeLauncher.new(nil))
        logger = StubLogger.new
        NewRelic::Agent.stub(:logger, logger) do
          1.upto(11) do |i|
            sampler.instance_variable_set(:@consecutive_failures, i)
            sampler.send(:log_sample_failure, RuntimeError.new('boom'))
          end
        end

        # 1st and 10th of 11 total iterations should log; 2..9 and 11 should not.
        assert_equal 2, logger.errors.size, "logged at: #{logger.errors.map { |m| m[/failures: \d+/] }}"
        assert_match(/failures: 1\)/, logger.errors[0])
        assert_match(/failures: 10\)/, logger.errors[1])
      end

      def test_log_sample_failure_respects_time_floor
        sampler = PumaStatsSampler.new(FakeLauncher.new(nil))
        logger = StubLogger.new

        sampler.instance_variable_set(:@consecutive_failures, 1)
        sampler.stub(:monotonic_now, 0.0) do
          NewRelic::Agent.stub(:logger, logger) do
            sampler.send(:log_sample_failure, RuntimeError.new('boom'))
          end
        end
        # Second iteration would normally be suppressed by the every-Nth rule.
        # Push past the time floor so it should re-surface.
        sampler.instance_variable_set(:@consecutive_failures, 2)
        sampler.stub(:monotonic_now, NewRelic::Agent::PumaStatsSampler::LOG_FAILURE_TIME_FLOOR_SECONDS + 1.0) do
          NewRelic::Agent.stub(:logger, logger) do
            sampler.send(:log_sample_failure, RuntimeError.new('boom again'))
          end
        end

        assert_equal 2, logger.errors.size,
          'expected time floor to re-log a sustained failure beyond the every-Nth window'
      end

      # --- report_metrics failure isolation ---------------------------------

      def test_report_metrics_failure_does_not_count_against_sample_backoff
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))

        ::NewRelic::Agent.stub(:record_metric, ->(*) { raise 'metric store down' }) do
          sampler.send(:sample)
        end

        assert_equal 0, sampler.instance_variable_get(:@consecutive_failures),
          'metric-store failures must not trigger the Puma-stats failure backoff'
        assert_equal 1, sampler.instance_variable_get(:@consecutive_report_failures),
          'metric-store failures should accumulate against their own counter'
      end

      def test_report_metrics_failure_logging_is_throttled
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))
        logger = StubLogger.new

        ::NewRelic::Agent.stub(:record_metric, ->(*) { raise 'metric store down' }) do
          NewRelic::Agent.stub(:logger, logger) do
            sampler.stub(:monotonic_now, 0.0) do
              1.upto(11) { sampler.send(:sample) }
            end
          end
        end

        # Same cadence as sample failures: log iteration 1 and 10 only.
        report_errors = logger.errors.select { |m| m.include?('Error recording Puma timeslice metrics') }

        assert_equal 2, report_errors.size,
          "expected throttled report-failure logging (1st + 10th), got #{report_errors.size}: #{report_errors.inspect}"
      end

      def test_report_metrics_failure_logging_respects_time_floor
        # Ensures log_report_failure honours the time floor independently —
        # so the report-side throttle keeps working if its branch in
        # should_log? ever diverges from the sample-side.
        sampler = PumaStatsSampler.new(FakeLauncher.new(SINGLE_STATS))
        logger = StubLogger.new

        ::NewRelic::Agent.stub(:record_metric, ->(*) { raise 'metric store down' }) do
          NewRelic::Agent.stub(:logger, logger) do
            sampler.stub(:monotonic_now, 0.0) { sampler.send(:sample) }
            # Second call would normally be suppressed (consecutive=2,
            # neither first nor every-Nth). Push past the floor: should log.
            sampler.stub(:monotonic_now, NewRelic::Agent::PumaStatsSampler::LOG_FAILURE_TIME_FLOOR_SECONDS + 1.0) do
              sampler.send(:sample)
            end
          end
        end

        report_errors = logger.errors.select { |m| m.include?('Error recording Puma timeslice metrics') }

        assert_equal 2, report_errors.size,
          'expected time floor to re-log a sustained report failure beyond the every-Nth window'
      end

      private

      # Captures only error-level messages; #log_exception is called too but
      # at :debug, which we don't need to assert against.
      class StubLogger
        attr_reader :errors

        def initialize
          @errors = []
        end

        def error(*args)
          @errors << args.first.to_s
        end

        def log_exception(*); end
      end

      def thread_completes?(timeout = 5, &block)
        Thread.new(&block).join(timeout)
      end
    end
  end
end
