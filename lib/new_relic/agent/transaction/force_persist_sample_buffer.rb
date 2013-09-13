# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/transaction_sample_buffer'

module NewRelic
  module Agent
    class Transaction
      class ForcePersistSampleBuffer < TransactionSampleBuffer

        MAX_SAMPLES = 10

        def max_samples
          MAX_SAMPLES
        end

        def allow_sample?(sample)
          sample.force_persist
        end

      end
    end
  end
end
