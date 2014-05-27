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
          @total_time_s = 0
          @lock         = Mutex.new
        end

        class ProfilerNotEnabledError < StandardError
          def initialize
            super("total_time is not available if GC::Profiler isn't enabled")
          end
        end

        def total_time_s
          raise ProfilerNotEnabledError.new unless NewRelic::LanguageSupport.gc_profiler_enabled?

          # There's a race here if the next two lines don't execute as an atomic
          # unit - we may end up double-counting some GC time in that scenario.
          # Locking around them guarantees atomicity of the read/increment/reset
          # sequence.
          @lock.synchronize do
            # The Ruby 1.9.x docs claim that GC::Profiler.total_time returns
            # a value in milliseconds. They are incorrect - both 1.9.x and 2.x
            # return values in seconds.
            @total_time_s += ::GC::Profiler.total_time
            ::GC::Profiler.clear
          end

          @total_time_s
        end
      end
    end
  end
end
