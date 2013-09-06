# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class TransactionTracer
        NO_SAMPLES = [].freeze

        def visit_segment(*)
          # no-op
        end
      end
    end
  end
end
