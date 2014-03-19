# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# The GC::Profiler class available on MRI has to be reset periodically to avoid
# memory "leaking" in the underlying implementation. However, it's a major
# bummer for how we want to gather those statistics.
#
# This class comes to the rescue. It relies on being the only party to reset
# the underlying GC::Profiler, but otherwise gives us a steadily increasing
# total time.
module NewRelic
  module Agent
    module VM
      class MonotonicGCProfiler
        def initialize
          @total_time = 0
        end

        class ProfilerNotEnabledError < StandardError
          def initialize
            super("total_time is not available if GC::Profiler isn't enabled")
          end
        end

        def total_time
          raise ProfilerNotEnabledError.new unless NewRelic::LanguageSupport.gc_profiler_enabled?

          # There's a race here if the next two lines don't execute as an atomic
          # unit - we may end up double-counting some GC time in that scenario.
          #
          # The window during which this race can exhibit is small: two
          # transactions must be starting or ending at exactly the same time.
          #
          # The likelihood of the race exhibiting is low enough, and the fallout
          # (slightly over-counted GC time) small enough that we've decided for
          # now to not introduce a lock here that would wrap these two lines and
          # prevent the race.
          #
          # The thinking is that the overhead of acquiring / releasing the lock
          # would have just as much of a distorting effect on the data we're
          # gathering as would the race itself.
          #
          @total_time += ::GC::Profiler.total_time
          ::GC::Profiler.clear

          @total_time
        end
      end
    end
  end
end
