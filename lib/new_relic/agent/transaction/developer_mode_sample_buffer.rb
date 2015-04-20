# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/transaction_sample_buffer'

module NewRelic
  module Agent
    class Transaction
      class DeveloperModeSampleBuffer < TransactionSampleBuffer

        CAPACITY = 100

        def capacity
          max_capacity
        end

        # Dev mode is allowed more than the typical upper limit.
        # Sidestep normal cap by overriding max_capacity.
        def max_capacity
          CAPACITY
        end

        def harvest_samples
          NO_SAMPLES
        end

        def enabled?
          Agent.config[:developer_mode]
        end

        # Truncate to the last capacity samples we've received
        def truncate_samples
          @samples = @samples.last(capacity)
        end

        # We don't hold onto previously trapped transactions on harvest
        # We've already got all the traces we want, thank you!
        def store_previous(*)
        end

        # Captures the stack trace for a node
        # This is expensive and not for production mode
        def visit_node(node)
          return unless enabled? && node

          trace = strip_newrelic_frames(caller)
          trace = trace.first(40) if trace.length > 40
          node[:backtrace] = trace
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
