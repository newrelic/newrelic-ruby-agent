# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'thread'

module NewRelic
  module Agent
    module VM
      class RubiniusVM
        def snapshot
          snap = Snapshot.new
          gather_stats(snap)
          snap
        end

        def gather_stats(snap)
          gather_gc_stats(snap)
          gather_thread_stats(snap)
        end

        def gather_gc_stats(snap)
          snap.gc_runs = GC.count

          # Rubinius::Metrics is available since Rubinius 2.3
          if has_metrics?
            gather_stats_from_metrics(snap)
          else
            gather_stats_from_gc_stat(snap)
          end

          gather_gc_time(snap)
        end

        # The '+ 0' bits in here are a workaround for a Rubinius bug wherein
        # Rubinius::Metrics.data returns 0's as Bignums, and these Bignums
        # cannot be safely subtraced from Fixnums. The + 0  has the effect of
        # truncating to a Fixnum if possible without loss of precision.
        # See https://github.com/rubinius/rubinius/issues/3316
        def gather_stats_from_metrics(snap)
          snap.major_gc_count = metric(:'gc.immix.count') + 0
          snap.minor_gc_count = metric(:'gc.young.count') + 0

          if has_metric_totals?
            # Rubinius < 2.5.8 metric names
            snap.heap_live = metric(:'memory.large.objects.current') +
              metric(:'memory.young.objects.current') +
              metric(:'memory.immix.objects.current')

            snap.total_allocated_object =
              metric(:'memory.large.objects.total') +
              metric(:'memory.young.objects.total') +
              metric(:'memory.immix.objects.total')

            snap.method_cache_invalidations = metric(:'vm.inline_cache.resets') + 0
          else
            # Rubinius >= 2.5.8 metric names and no total metrics
            snap.heap_live = metric(:'memory.large.objects') +
              metric(:'memory.young.objects') +
              metric(:'memory.immix.objects')

            snap.method_cache_invalidations = metric(:'machine.inline_cache.resets') + 0
          end
        end

        def gather_stats_from_gc_stat(snap)
          gc_stats = GC.stat[:gc]

          if gc_stats
            snap.major_gc_count = gc_stats[:full][:count] if gc_stats[:full]
            snap.minor_gc_count = gc_stats[:young][:count] if gc_stats[:young]
          end
        end

        def gather_gc_time(snap)
          if GC.respond_to?(:time)
            # On Rubinius GC.time returns a time in miliseconds, not seconds.
            snap.gc_total_time = GC.time / 1000
          end
        end

        def gather_thread_stats(snap)
          snap.thread_count = Thread.list.size
        end

        def has_metrics?
          Rubinius.const_defined?(:Metrics)
        end

        def metric(key)
          Rubinius::Metrics.data[key]
        end

        def has_metric?(key)
          Rubinius::Metrics.data.keys.include? key
        end

        def has_metric_totals?
          has_metric? :'memory.large.objects.total'
        end

        def supports?(key)
          if has_metrics?
            case key
            when :major_gc_count
              true
            when :minor_gc_count
              true
            when :heap_live
              true
            when :total_allocated_object
              has_metric_totals?
            when :method_cache_invalidations
              true
            when :gc_runs
              true
            when :gc_total_time
              GC.respond_to?(:time)
            when :thread_count
              true
            else
              false
            end
          else
            case key
            when :major_gc_count
              true
            when :minor_gc_count
              true
            when :thread_count
              true
            else
              false
            end
          end
        end
      end
    end
  end
end
