# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'thread'
require 'new_relic/agent/vm/snapshot'

module NewRelic
  module Agent
    module VM
      class MriVM
        def snapshot
          snap = Snapshot.new
          gather_stats(snap)
          snap
        end

        def gather_stats(snap)
          gather_gc_stats(snap)
          gather_ruby_vm_stats(snap)
          gather_thread_stats(snap)
          gather_gc_time(snap)
        end

        def gather_gc_stats(snap)
          gather_gc_runs(snap) if supports?(:gc_runs)
          gather_derived_stats(snap)
        end

        def gather_gc_runs(snap)
          snap.gc_runs = GC.count
        end

        def gather_derived_stats(snap)
          stat = GC.stat
          snap.total_allocated_object = stat.fetch(:total_allocated_objects, nil)
          snap.major_gc_count = stat.fetch(:major_gc_count, nil)
          snap.minor_gc_count = stat.fetch(:minor_gc_count, nil)
          snap.heap_live = stat.fetch(:heap_live_slots, nil)
          snap.heap_free = stat.fetch(:heap_free_slots, nil)
        end

        def gather_gc_time(snap)
          return unless supports?(:gc_total_time)

          snap.gc_total_time = NewRelic::Agent.instance.monotonic_gc_profiler.total_time_s
        end

        def gather_ruby_vm_stats(snap)
          if supports?(:method_cache_invalidations)
            snap.method_cache_invalidations = RubyVM.stat[:global_method_state]
          end

          if supports?(:constant_cache_invalidations)
            snap.constant_cache_invalidations = gather_constant_cache_invalidations
          end

          if supports?(:constant_cache_misses)
            snap.constant_cache_misses = gather_constant_cache_misses
          end
        end

        def gather_constant_cache_invalidations
          RubyVM.stat[RUBY_VERSION >= '3.2.0' ? :constant_cache_invalidations : :global_constant_state]
        end

        def gather_constant_cache_misses
          RubyVM.stat[:constant_cache_misses]
        end

        def gather_thread_stats(snap)
          snap.thread_count = Thread.list.size
        end

        def supports?(key)
          case key
          when :gc_runs,
            :total_allocated_object,
            :heap_live,
            :heap_free,
            :thread_count,
            :major_gc_count,
            :minor_gc_count,
            :constant_cache_invalidations
            true
          when :gc_total_time
            NewRelic::LanguageSupport.gc_profiler_enabled?
          when :method_cache_invalidations
            RUBY_VERSION < '3.0.0'
          when :constant_cache_misses
            RUBY_VERSION >= '3.2.0'
          else
            false
          end
        end
      end
    end
  end
end
