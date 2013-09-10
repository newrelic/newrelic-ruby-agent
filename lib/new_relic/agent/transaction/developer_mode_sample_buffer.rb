# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/transaction_sample_buffer'

module NewRelic
  module Agent
    class Transaction
      class DeveloperModeSampleBuffer < TransactionSampleBuffer
        def max_samples
          100
        end

        def harvest_samples
          NO_SAMPLES
        end

        def enabled?
          Agent.config[:developer_mode]
        end

        # Leave samples in their arrival order
        def sort_for_truncation
          nil
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
