# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class IntrinsicAttributes < Attributes
        def all
          @attributes
        end

        EMPTY_HASH = {}.freeze

        def for_destination(destination)
          if destination == NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER ||
             destination == NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR
            @attributes
          else
            EMPTY_HASH
          end
        end
      end
    end
  end
end
