# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module VM
      class Snapshot
        attr_accessor :gc_total_time, :gc_runs, :major_gc_count, :minor_gc_count,
          :total_allocated_object, :heap_live, :heap_free,
          :method_cache_invalidations, :constant_cache_invalidations,
          :constant_cache_misses, :thread_count, :taken_at

        def initialize
          @taken_at = Process.clock_gettime(Process::CLOCK_REALTIME)
        end

        def method_missing(method, *args, &blk)
          return self.send(:method, args, blk) unless method.to_s.end_with?('=')

          self.instance_variable_set("@#{method[0..-2]}".to_sym, args.first)
        end
      end
    end
  end
end
