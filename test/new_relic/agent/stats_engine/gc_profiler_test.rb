# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::StatsEngine
  class GCProfilerTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data

      stub_gc_profiling_enabled
      GCProfiler.reset
    end

    def teardown
      NewRelic::Agent.drop_buffered_data
      GCProfiler.reset
    end

    def test_init_profiler_for_rails_bench
      return unless defined?(::GC) && ::GC.respond_to?(:collections)

      ::GC.stubs(:time)
      ::GC.stubs(:collections)

      assert_equal(GCProfiler::RailsBenchProfiler,
                   GCProfiler.init.class)
    end

    def test_init_profiler_for_ruby_19_and_greater
      return unless defined?(::GC::Profiler)
      return if NewRelic::LanguageSupport.using_engine?('jruby')

      ::GC::Profiler.stubs(:enabled?).returns(true)

      assert_equal(GCProfiler::CoreGCProfiler,
                   GCProfiler.init.class)
    end

    def test_init_profiler_for_rbx_uses_stdlib
      return unless defined?(::Rubinius::GC)

      assert_equal(GCProfiler::CoreGCProfiler,
                   GCProfiler.init.class)
    end

    def test_record_delta_returns_nil_when_snapshots_are_nil
      result = GCProfiler.record_delta(nil, nil)
      assert_nil(result)
      assert_metrics_not_recorded([GCProfiler::GC_ROLLUP, GCProfiler::GC_WEB, GCProfiler::GC_OTHER])
    end

    using_jruby       = NewRelic::LanguageSupport.jruby?
    using_ree         = NewRelic::LanguageSupport.ree?
    using_ruby18      = NewRelic::LanguageSupport.using_version?('1.8')
    using_ruby19_plus = !using_ruby18

    # Only run these tests in environments where GCProfiler is usable
    if !using_jruby && (using_ree || using_ruby19_plus)
      def test_record_delta_returns_delta_in_seconds
        GCProfiler.init

        start_snapshot = GCProfiler::GCSnapshot.new(1.0, 1)
        end_snapshot   = GCProfiler::GCSnapshot.new(2.5, 3)

        result = GCProfiler.record_delta(start_snapshot, end_snapshot)
        assert_equal(1.5, result)
      end

      def test_record_delta_records_gc_time_and_call_count_in_metric
        GCProfiler.init
        start_snapshot = GCProfiler::GCSnapshot.new(1.0, 1)
        end_snapshot   = GCProfiler::GCSnapshot.new(2.5, 3)

        GCProfiler.record_delta(start_snapshot, end_snapshot)

        assert_gc_metrics(GCProfiler::GC_OTHER,
                          :call_count => 2, :total_call_time => 1.5)
      end

      # This test is asserting that the implementation of GC::Profiler provided by
      # the language implementation currently in use behaves in the way we assume.
      # Specifically, we expect that GC::Profiler.clear will *not* reset GC.count.
      def test_gc_profiler_clear_does_not_reset_count
        return unless defined?(::GC::Profiler)

        GC::Profiler.enable

        count_before_allocations = GC.count
        100000.times { String.new }
        GC.start
        count_after_allocations = GC.count
        GC::Profiler.clear
        count_after_clear = GC.count

        assert_operator count_before_allocations, :<=, count_after_allocations
        assert_operator count_after_allocations,  :<=, count_after_clear
      ensure
        GC::Profiler.disable if defined?(::GC::Profiler)
      end

      def test_take_snapshot_should_return_snapshot
        stub_gc_timer(5.0)
        stub_gc_count(10)

        snapshot = GCProfiler.take_snapshot

        assert_equal(5.0, snapshot.gc_time_s)
        assert_equal(10,  snapshot.gc_call_count)
      end

      def test_collect_gc_data
        stub_gc_timer(1.0)
        stub_gc_count(1)

        with_config(:'transaction_tracer.enabled' => true) do
          in_transaction do
            stub_gc_timer(4.0)
            stub_gc_count(3)
          end
        end

        assert_gc_metrics(GCProfiler::GC_OTHER,
                          :call_count => 2, :total_call_time => 3.0)
        assert_metrics_not_recorded(GCProfiler::GC_WEB)

        tracer = NewRelic::Agent.instance.transaction_sampler
        assert_equal(3.0, attributes_for(tracer.last_sample, :intrinsic)[:gc_time])
      end

      def test_collect_gc_data_web
        stub_gc_timer(1.0)
        stub_gc_count(1)

        with_config(:'transaction_tracer.enabled' => true) do
          in_web_transaction do
            stub_gc_timer(4.0)
            stub_gc_count(3)
          end
        end

        assert_gc_metrics(GCProfiler::GC_WEB,
                          :call_count => 2, :total_call_time => 3.0)
        assert_metrics_not_recorded(GCProfiler::GC_OTHER)
      end
    end

    def assert_gc_metrics(name, expected_values={})
      assert_metrics_recorded(
        [GCProfiler::GC_ROLLUP, ''] => expected_values,
        name => expected_values
      )
      assert_metrics_not_recorded([[GCProfiler::GC_ROLLUP, 'dummy']])
    end

    # gc_timer_value should be specified in seconds
    def stub_gc_timer(gc_timer_value_s)
      profiler = GCProfiler.init

      gc_timer_value_us = gc_timer_value_s * 1_000_000

      case profiler
      when GCProfiler::CoreGCProfiler
        NewRelic::Agent.instance.monotonic_gc_profiler.stubs(:total_time_s).returns(gc_timer_value_s)
      when GCProfiler::RailsBenchProfiler
        ::GC.stubs(:time).returns(gc_timer_value_us)
      end
    end

    def stub_gc_count(gc_count)
      profiler = GCProfiler.init

      case profiler
      when GCProfiler::CoreGCProfiler
        ::GC.stubs(:count).returns(gc_count)
      when GCProfiler::RailsBenchProfiler
        ::GC.stubs(:collections).returns(gc_count)
      end
    end

    def stub_gc_profiling_enabled
      if defined?(::GC::Profiler)
        ::GC::Profiler.stubs(:enabled?).returns(true)
      end
    end
  end
end
