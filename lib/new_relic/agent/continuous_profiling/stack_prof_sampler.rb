# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module ContinuousProfiling
      # Thin wrapper around the three StackProf calls the continuous profiler needs.
      # Kept separate from Session so Session's lifecycle logic can be unit tested
      # without the real `stackprof` gem loaded.
      class StackProfSampler
        MICROSECONDS_PER_SECOND = 1_000_000
        MODE_METRIC_PREFIX = 'Supportability/Ruby/Profiling/Mode'

        def start
          mode = NewRelic::Agent.config[:'profiling.mode']
          NewRelic::Agent.increment_metric("#{MODE_METRIC_PREFIX}/#{mode}")
          # StackProf's raw_sample_timestamps use CLOCK_MONOTONIC, unrelated to wall-clock time.
          # Capturing both clocks at the same instant lets ProfileEncoder convert a tick's
          # monotonic timestamp back to wall-clock time to match against Transaction#start_time.
          @monotonic_to_realtime_offset =
            Process.clock_gettime(Process::CLOCK_REALTIME) - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          StackProf.start(
            mode: mode.to_sym,
            interval: sample_interval_in_microseconds,
            raw: true
          )
        end

        def stop_and_collect
          StackProf.stop
          StackProf.results.merge(clock_offset: @monotonic_to_realtime_offset)
        end

        private

        def sample_interval_in_microseconds
          (NewRelic::Agent.config[:'profiling.sample_period'] * MICROSECONDS_PER_SECOND).to_i
        end
      end
    end
  end
end
