# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# -*- coding: utf-8 -*-
module NewRelic
  module Agent
    class StatsEngine
      module GCProfiler
        GCSnapshot = Struct.new(:gc_time_s, :gc_call_count)

        def self.init
          return @profiler if @initialized
          @profiler = if RailsBenchProfiler.enabled?
            RailsBenchProfiler.new
          elsif CoreGCProfiler.enabled?
            CoreGCProfiler.new
          end
          @initialized = true
          @profiler
        end

        def self.reset
          @profiler    = nil
          @initialized = nil
        end

        def self.take_snapshot
          init
          if @profiler
            GCSnapshot.new(@profiler.call_time_s, @profiler.call_count)
          else
            nil
          end
        end

        def self.record_delta(start_snapshot, end_snapshot)
          if @profiler && start_snapshot && end_snapshot
            elapsed_gc_time_s = end_snapshot.gc_time_s - start_snapshot.gc_time_s
            num_calls         = end_snapshot.gc_call_count - start_snapshot.gc_call_count
            record_gc_metric(num_calls, elapsed_gc_time_s)

            @profiler.reset
            elapsed_gc_time_s
          end
        end

        def self.record_gc_metric(call_count, elapsed)
          NewRelic::Agent.agent.stats_engine.record_metrics(gc_metric_specs) do |stats|
            stats.call_count           += call_count
            stats.total_call_time      += elapsed
            stats.total_exclusive_time += elapsed
          end
        end

        GC_ROLLUP = 'GC/Transaction/all'.freeze
        GC_OTHER  = 'GC/Transaction/allOther'.freeze
        GC_WEB    = 'GC/Transaction/allWeb'.freeze

        SCOPE_PLACEHOLDER = NewRelic::Agent::StatsEngine::MetricStats::SCOPE_PLACEHOLDER

        GC_ROLLUP_SPEC       = NewRelic::MetricSpec.new(GC_ROLLUP)
        GC_OTHER_SPEC        = NewRelic::MetricSpec.new(GC_OTHER)
        GC_OTHER_SCOPED_SPEC = NewRelic::MetricSpec.new(GC_OTHER, SCOPE_PLACEHOLDER)
        GC_WEB_SPEC          = NewRelic::MetricSpec.new(GC_WEB)
        GC_WEB_SCOPED_SPEC   = NewRelic::MetricSpec.new(GC_WEB, SCOPE_PLACEHOLDER)

        def self.gc_metric_specs
          # The .dup call on the scoped MetricSpec here is necessary because
          # metric specs with non-empty scopes will have their scopes mutated
          # when the metrics are merged into the global stats hash, and we don't
          # want to mutate the original MetricSpec.
          if NewRelic::Agent::Transaction.recording_web_transaction?
            [GC_ROLLUP_SPEC, GC_WEB_SPEC, GC_WEB_SCOPED_SPEC.dup]
          else
            [GC_ROLLUP_SPEC, GC_OTHER_SPEC, GC_OTHER_SCOPED_SPEC.dup]
          end
        end

        class RailsBenchProfiler
          def self.enabled?
            ::GC.respond_to?(:time) && ::GC.respond_to?(:collections)
          end

          def call_time_s
            ::GC.time.to_f / 1_000_000 # this value is reported in us, so convert to s
          end

          def call_count
            ::GC.collections
          end

          def reset
            ::GC.clear_stats
          end
        end

        class CoreGCProfiler
          def self.enabled?
            NewRelic::LanguageSupport.gc_profiler_enabled?
          end

          def call_time_s
            NewRelic::Agent.instance.monotonic_gc_profiler.total_time_s
          end

          def call_count
            ::GC.count
          end

          # When using GC::Profiler, it's important to periodically call
          # GC::Profiler.clear in order to avoid unbounded growth in the number
          # of GC recordds that are stored. However, we actually do this
          # internally within MonotonicGCProfiler on calls to #total_time_s,
          # so the reset here is a no-op.
          def reset; end
        end
      end
    end
  end
end
