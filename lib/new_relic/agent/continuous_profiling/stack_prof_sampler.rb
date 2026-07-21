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
          mode = NewRelic::Agent.config[:'continuous_profiler.mode']
          NewRelic::Agent.increment_metric("#{MODE_METRIC_PREFIX}/#{mode}")
          StackProf.start(
            mode: mode.to_sym,
            interval: sample_interval_in_microseconds,
            raw: true
          )
        end

        def stop_and_collect
          StackProf.stop
          StackProf.results
        end

        private

        def sample_interval_in_microseconds
          (NewRelic::Agent.config[:'continuous_profiler.sample_period'] * MICROSECONDS_PER_SECOND).to_i
        end
      end
    end
  end
end
