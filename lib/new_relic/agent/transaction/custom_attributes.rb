# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/attributes'

module NewRelic
  module Agent
    class Transaction
      class CustomAttributes < Attributes
        KEY_LIMIT = 255

        def add(key, value)
          if key.length > KEY_LIMIT
            NewRelic::Agent.logger.warn("Custom attribute key '#{key}' was longer than limit of #{KEY_LIMIT}. This attribute will be dropped.")
            return
          end

          super
        end

      end
    end
  end
end
