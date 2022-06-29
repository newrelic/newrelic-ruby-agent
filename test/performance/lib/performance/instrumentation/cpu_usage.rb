# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

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
          :cpu_time_user => @times_after.utime - @times_before.utime,
          :cpu_time_system => @times_after.stime - @times_before.stime
        }
      end
    end
  end
end
