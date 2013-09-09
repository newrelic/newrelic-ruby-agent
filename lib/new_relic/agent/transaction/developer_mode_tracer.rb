# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/transaction_tracer'

module NewRelic
  module Agent
    class Transaction
      class DeveloperModeTracer < TransactionTracer
        attr_reader   :samples

        MAX_SAMPLES = 100

        def initialize
          @samples = []
        end

        def reset!
          @samples = []
        end

        def harvest_samples
          NO_SAMPLES
        end

        def enabled?
          Agent.config[:developer_mode]
        end

        def store(sample)
          return unless enabled?

          @samples << sample
          truncate_samples
        end

        def truncate_samples
          if @samples.length > MAX_SAMPLES
            @samples = @samples.last(MAX_SAMPLES)
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
