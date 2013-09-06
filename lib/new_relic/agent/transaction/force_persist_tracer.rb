# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/transaction_tracer'

module NewRelic
  module Agent
    class Transaction
      class ForcePersistTracer < TransactionTracer
        attr_accessor :samples

        def initialize
          @samples = []
        end

        def reset!
          @samples = []
        end

        def harvest_samples
          @samples
        ensure
          reset!
        end

        def store(sample)
          @samples << sample if sample.force_persist
          truncate_samples
        end

        def truncate_samples
          if @samples.length > 15
            @samples.sort! {|a,b| b.duration <=> a.duration}
            @samples = @samples.last(15)
          end
        end
      end
    end
  end
end
