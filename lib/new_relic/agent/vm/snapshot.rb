# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module VM
      class Snapshot
        attr_accessor :gc_runs, :major_gc_count, :minor_gc_count,
                      :total_allocated_object, :heap_live, :heap_free,
                      :method_cache_invalidations, :constant_cache_invalidations,
                      :thread_count
      end
    end
  end
end
