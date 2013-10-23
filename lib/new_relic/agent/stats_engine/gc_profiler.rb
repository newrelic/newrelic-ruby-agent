# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# -*- coding: utf-8 -*-
module NewRelic
  module Agent
    class StatsEngine
      module GCProfiler
        def self.init
          @profiler = RailsBenchProfiler.new if RailsBenchProfiler.enabled?
          @profiler = CoreGCProfiler.new if CoreGCProfiler.enabled?
          @profiler = LegacyRubiniusProfiler.new if LegacyRubiniusProfiler.enabled?
          @profiler
        end

        def self.capture
          @profiler.capture if @profiler
        end

        class Profiler
          def initialize
            if self.class.enabled?
              @last_timestamp = call_time
              @last_count = call_count
            end
          end

          def capture
            return unless self.class.enabled?
            return if !scope_stack.empty? && scope_stack.last.name == "GC/cumulative"

            num_calls = call_count - @last_count
            # microseconds to seconds
            elapsed = (call_time - @last_timestamp).to_f / 1_000_000.0
            @last_timestamp = call_time
            @last_count = call_count
            reset

            record_gc_metric(num_calls, elapsed)
            elapsed
          end

          def reset; end

          protected

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

          def scope_stack
            NewRelic::Agent::TransactionState.get.stats_scope_stack
          end
        end

        class RailsBenchProfiler < Profiler
          def self.enabled?
            ::GC.respond_to?(:time) && ::GC.respond_to?(:collections)
          end

          # microseconds spent in GC
          def call_time
            ::GC.time # this should already be microseconds
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
            !NewRelic::LanguageSupport.using_engine?('jruby') &&
              defined?(::GC::Profiler) && ::GC::Profiler.enabled?
          end

          # microseconds spent in GC
          # 1.9 total_time returns seconds.  Don't trust the docs.  It's seconds.
          def call_time
            ::GC::Profiler.total_time * 1_000_000.0 # convert seconds to microseconds
          end

          def call_count
            ::GC.count
          end

          def reset
            ::GC::Profiler.clear
            @last_timestamp = 0
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

          def call_time
            ::Rubinius::GC.time * 1000
          end

          def call_count
            ::Rubinius::GC.count
          end
        end
      end
    end
  end
end
