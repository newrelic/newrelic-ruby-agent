# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  module Instrumentation
    class MRIGCStats < Instrumentor
      platforms :mri_22, :mri_23, :mri_24, :mri_25, :mri_26, :mri_27, :mri_30, :mri_31
      on_by_default

      def before(*)
        @stats_before = GC.stat
      end

      def after(*)
        @stats_after = GC.stat
      end

      def results
        heap_live_before = @stats_before[:heap_live_slots] || @stats_before[:heap_live_num] || @stats_before[:heap_live_slot]
        heap_live_after = @stats_after[:heap_live_slots] || @stats_after[:heap_live_num] || @stats_after[:heap_live_slot]

        res = {
          :gc_runs => @stats_after[:count] - @stats_before[:count],
          :live_objects => heap_live_after - heap_live_before
        }
        allocs_before = @stats_before[:total_allocated_objects] || @stats_before[:total_allocated_object]
        allocs_after = @stats_after[:total_allocated_objects] || @stats_after[:total_allocated_object]
        res[:allocations] = allocs_after - allocs_before
        retained_before = @stats_before[:old_objects] || @stats_before[:old_object]
        retained_after = @stats_after[:old_objects] || @stats_after[:old_object]
        res[:retained] = retained_after - retained_before
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
          :live_objects => @live_objects_after - @live_objects_before
        }
      end
    end
  end
end
