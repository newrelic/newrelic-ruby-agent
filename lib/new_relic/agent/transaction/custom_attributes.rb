# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/attributes'

module NewRelic
  module Agent
    class Transaction
      class CustomAttributes < Attributes

        COUNT_LIMIT = 64

        def add(key, value)
          if @attributes.size >= COUNT_LIMIT
            unless @already_warned_count_limit
              NewRelic::Agent.logger.warn("Custom attributes count exceeded limit of #{COUNT_LIMIT}. Any additional custom attributes during this transaction will be dropped.")
              @already_warned_count_limit = true
            end
            return
          end

          if exceeds_bytesize_limit?(key, KEY_LIMIT)
            NewRelic::Agent.logger.warn("Custom attribute key '#{key}' was longer than limit of #{KEY_LIMIT}. This attribute will be dropped.")
            return
          end

          super
        end
      end
    end
  end
end
