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

        def total_time
          @total_time += ::GC::Profiler.total_time
          ::GC::Profiler.clear
          @total_time
        end
      end
    end
  end
end
