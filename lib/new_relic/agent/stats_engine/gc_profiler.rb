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
          elsif LegacyRubiniusProfiler.enabled?
            LegacyRubiniusProfiler.new
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
            elapsed_gc_time_s = end_snapshot.gc_time_s     - start_snapshot.gc_time_s
            num_calls         = end_snapshot.gc_call_count - start_snapshot.gc_call_count

            @profiler.record_gc_metric(num_calls, elapsed_gc_time_s)
            @profiler.reset
            elapsed_gc_time_s
          end
        end

        class Profiler
          def reset; end

          def record_gc_metric(num_calls, elapsed)
            if num_calls > 0
              # GC stats are collected into a blamed metric which allows
              # us to show the stats controller by controller
              NewRelic::Agent.instance.stats_engine \
                .record_metrics('GC/cumulative', nil, :scoped => true) do |stat|
                stat.record_multiple_data_points(elapsed, num_calls)
              end
            end
          end
        end

        class RailsBenchProfiler < Profiler
          def self.enabled?
            ::GC.respond_to?(:time) && ::GC.respond_to?(:collections)
          end

          def call_time_s
            ::GC.time / 1_000_000 # this value is reported in us, so convert to s
          end

          def call_count
            ::GC.collections
          end

          def reset
            ::GC.clear_stats
          end
        end

        class CoreGCProfiler < Profiler
          def self.enabled?
            NewRelic::LanguageSupport.gc_profiler_enabled?
          end

          # In 1.9+, GC::Profiler.total_time returns seconds.
          # Don't trust the docs. It's seconds.
          def call_time_s
            NewRelic::Agent.instance.monotonic_gc_profiler.total_time
          end

          def call_count
            ::GC.count
          end
        end

        # Only present for legacy support of Rubinius < 2.0.0
        class LegacyRubiniusProfiler < Profiler
          def self.enabled?
            self.has_rubinius_profiler? && !has_core_profiler?
          end

          def self.has_rubinius_profiler?
            defined?(::Rubinius) && defined?(::Rubinius::GC) && ::Rubinius::GC.respond_to?(:count)
          end

          def self.has_core_profiler?
            defined?(::GC::Profiler)
          end

          def call_time_s
            ::Rubinius::GC.time / 1000
          end

          def call_count
            ::Rubinius::GC.count
          end
        end
      end
    end
  end
end
