# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class DeveloperModeTracer
        attr_accessor :max_samples
        attr_reader   :samples

        def initialize
          @samples = []
          @max_samples = 100
        end

        def reset!
          @samples = []
        end

        NO_SAMPLES = [].freeze

        def harvest_samples
          NO_SAMPLES
        end

        def enabled?
          Agent.config[:developer_mode]
        end

        def store(sample)
          return unless enabled?

          @samples ||= []
          @samples << sample
          truncate_samples
        end

        def truncate_samples
          if @samples.length > @max_samples
            @samples = @samples.last(@max_samples)
          end
        end

        # Captures the stack trace for a segment
        # This is expensive and not for production mode
        def visit_segment(segment)
          return unless enabled? && segment

          trace = strip_newrelic_frames(caller)
          trace = trace.first(40) if trace.length > 40
          segment[:backtrace] = trace
        end

        def strip_newrelic_frames(trace)
          while trace.first =~/\/lib\/new_relic\/agent\//
            trace.shift
          end
          trace
        end

      end
    end
  end
end
