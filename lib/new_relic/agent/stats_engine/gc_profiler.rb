# -*- coding: utf-8 -*-
module NewRelic
  module Agent
    class StatsEngine
      module GCProfiler
        def self.init
          @profiler = RailsBench.new if RailsBench.enabled?
          @profiler = Ruby19.new if Ruby19.enabled?
          @profiler = Rubinius.new if Rubinius.enabled?
          @profiler = RubiniusAgent.new if RubiniusAgent.enabled?
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
              gc_stats = NewRelic::Agent.instance.stats_engine \
                .get_stats('GC/cumulative', true, false,
                           NewRelic::Agent::TransactionInfo.get.transaction_name)
              gc_stats.record_multiple_data_points(elapsed, num_calls)
            end
          end

          def scope_stack
            Thread::current[:newrelic_scope_stack] ||= []
          end
        end

        class RailsBench < Profiler
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

        class Ruby19 < Profiler
          def self.enabled?
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

        class Rubinius < Profiler
          def self.enabled?
            defined?(::Rubinius) && defined?(::Rubinius::GC) && ::Rubinius::GC.respond_to?(:count)
          end

          def call_time
            ::Rubinius::GC.time * 1000
          end

          def call_count
            ::Rubinius::GC.count
          end
        end

        class RubiniusAgent < Profiler
          def self.enabled?
            if NewRelic::LanguageSupport.using_engine?('rbx')
              require 'rubinius/agent'
              true
            else
              false
            end
          end

          def call_time
            agent = ::Rubinius::Agent.loopback
            (agent.get('system.gc.young.total_wallclock')[1] +
              agent.get('system.gc.full.total_wallclock')[1]) * 1000
          end

          def call_count
            agent = ::Rubinius::Agent.loopback
            agent.get('system.gc.young.count')[1] +
              agent.get('system.gc.full.count')[1]
          end
        end
      end
    end
  end
end
