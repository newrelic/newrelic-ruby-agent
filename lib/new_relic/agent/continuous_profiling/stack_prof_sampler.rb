# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module ContinuousProfiling
      class StackProfSampler
        MICROSECONDS_PER_SECOND = 1_000_000
        NANOSECONDS_PER_SECOND = 1_000_000_000

        def start
          mode = NewRelic::Agent.config[:'profiling.include'].to_sym
          # StackProf's raw_sample_timestamps use CLOCK_MONOTONIC; capturing both clocks here
          # lets ProfileEncoder convert a tick's monotonic timestamp back to wall-clock time.
          @window_start_realtime = Process.clock_gettime(Process::CLOCK_REALTIME)
          @monotonic_to_realtime_offset = @window_start_realtime - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          StackProf.start(
            mode: mode,
            interval: sample_interval(mode),
            raw: true
          )
        end

        def stop
          StackProf.stop
        end

        def stop_and_collect
          StackProf.stop
          window_end_realtime = Process.clock_gettime(Process::CLOCK_REALTIME)
          StackProf.results.merge(
            clock_offset: @monotonic_to_realtime_offset,
            window_start_realtime: @window_start_realtime,
            window_duration_nanos: ((window_end_realtime - @window_start_realtime) * NANOSECONDS_PER_SECOND).to_i
          )
        end

        private

        # StackProf's `interval` means microseconds of cpu/wall time for :cpu/:wall, but a count
        # of object allocations for :object.
        def sample_interval(mode)
          return NewRelic::Agent.config[:'profiling.object_allocation_interval'] if mode == :object

          sample_interval_in_microseconds
        end

        def sample_interval_in_microseconds
          (NewRelic::Agent.config[:'profiling.sample_period'] * MICROSECONDS_PER_SECOND).to_i
        end
      end
    end
  end
end
