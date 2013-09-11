# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sampler'

module NewRelic
  module Agent
    module Samplers
      class CpuSampler < NewRelic::Agent::Sampler
        attr_reader :last_time
        def initialize
          super :cpu
          @processor_count = NewRelic::Agent::SystemInfo.processor_count
          if @processor_count.nil?
            NewRelic::Agent.logger.warn("Failed to determine processor count, assuming 1")
            @processor_count = 1
          end
          poll
        end

        def record_user_util(value)
          NewRelic::Agent.record_metric("CPU/User/Utilization", value)
        end

        def record_system_util(value)
          NewRelic::Agent.record_metric("CPU/System/Utilization", value)
        end

        def record_usertime(value)
          NewRelic::Agent.record_metric("CPU/User Time", value)
        end

        def record_systemtime(value)
          NewRelic::Agent.record_metric("CPU/System Time", value)
        end

        def self.supported_on_this_platform?
          # Process.times on JRuby < 1.7.0 reports wall clock elapsed time,
          # not actual cpu time used, so this sampler can only be used on JRuby >= 1.7.0.
          if defined?(JRuby)
            return JRUBY_VERSION >= '1.7.0'
          end
          true
        end

        def poll
          now = Time.now
          t = Process.times
          if @last_time
            elapsed = now - @last_time
            return if elapsed < 1 # Causing some kind of math underflow

            usertime = t.utime - @last_utime
            systemtime = t.stime - @last_stime

            record_systemtime(systemtime) if systemtime >= 0
            record_usertime(usertime) if usertime >= 0

            # Calculate the true utilization by taking cpu times and dividing by
            # elapsed time X processor_count.

            record_user_util(usertime / (elapsed * @processor_count))
            record_system_util(systemtime / (elapsed * @processor_count))
          end
          @last_utime = t.utime
          @last_stime = t.stime
          @last_time = now
        end
      end
    end
  end
end
