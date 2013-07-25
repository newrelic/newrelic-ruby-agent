# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  module Instrumentation
    class CpuUsage < Instrumentor
      on_by_default

      def before(*)
        @times_before = Process.times
      end

      def after(*)
        @times_after = Process.times
      end

      def results
        {
          :cpu_time_user   => @times_after.utime - @times_before.utime,
          :cpu_time_system => @times_after.stime - @times_before.stime
        }
      end
    end
  end
end
