# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'thread'
require 'new_relic/agent/vm/snapshot'

module NewRelic
  module Agent
    module VM
      class JRubyVM
        def snapshot
          snap = Snapshot.new
          gather_stats(snap)
          snap
        end

        def gather_stats(snap)
          if supports?(:gc_runs)
            gc_stats = GC.stat
            snap.gc_runs = gc_stats[:count]
          end

          snap.thread_count = Thread.list.size
        end

        def supports?(key)
          case key
          when :gc_runs
            RUBY_VERSION >= "1.9.2"
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
