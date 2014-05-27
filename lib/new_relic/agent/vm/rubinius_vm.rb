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
          snap.gc_runs = GC.count

          gc_stats = GC.stat[:gc]
          if gc_stats
            snap.major_gc_count = gc_stats[:full][:count] if gc_stats[:full]
            snap.minor_gc_count = gc_stats[:young][:count] if gc_stats[:young]
          end

          snap.thread_count = Thread.list.size
        end

        SUPPORTED_KEYS = [
          :gc_runs,
          :major_gc_count,
          :minor_gc_count,
          :thread_count
        ].freeze

        def supports?(key)
          SUPPORTED_KEYS.include?(key)
        end
      end
    end
  end
end
