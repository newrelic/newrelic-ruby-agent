# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  module Instrumentation
    class MRIGCStats < Instrumentor
      platforms :mri_193, :mri_20, :mri_21, :mri_22
      on_by_default

      def before(*)
        @stats_before = GC.stat
      end

      def after(*)
        @stats_after = GC.stat
      end

      def results
        heap_live_before = @stats_before[:heap_live_slots] || @stats_before[:heap_live_num] || @stats_before[:heap_live_slot]
        heap_live_after  = @stats_after[:heap_live_slots]  || @stats_after[:heap_live_num]  || @stats_after[:heap_live_slot]

        res = {
          :gc_runs      => @stats_after[:count] - @stats_before[:count],
          :live_objects => heap_live_after      - heap_live_before
        }
        if RUBY_VERSION >= "2.0.0"
          allocs_before = @stats_before[:total_allocated_objects] || @stats_before[:total_allocated_object]
          allocs_after  = @stats_after[:total_allocated_objects]  || @stats_after[:total_allocated_object]
          res[:allocations] = allocs_after - allocs_before
        end
        res
      end
    end

    class REEGCStats < Instrumentor
      platforms :ree
      on_by_default

      def before(*)
        @allocations_before = ObjectSpace.allocated_objects
        @live_objects_before = ObjectSpace.live_objects
      end

      def after(*)
        @allocations_after = ObjectSpace.allocated_objects
        @live_objects_after = ObjectSpace.live_objects
      end

      def results
        {
          :allocations => @allocations_after - @allocations_before,
          :live_objects => @live_objects_after - @live_objects_before,
        }
      end
    end
  end
end
