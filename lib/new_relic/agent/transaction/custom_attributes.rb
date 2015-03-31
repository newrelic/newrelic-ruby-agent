# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/attributes'

module NewRelic
  module Agent
    class Transaction
      class CustomAttributes < Attributes
        KEY_LIMIT   = 255
        VALUE_LIMIT = 255
        COUNT_LIMIT = 64

        def add(key, value)
          if @attributes.count >= COUNT_LIMIT
            NewRelic::Agent.logger.warn("Custom attributes count exceeded limit of #{COUNT_LIMIT}. Additional custom attributes will be dropped.")
            return
          end

          if key.length > KEY_LIMIT
            NewRelic::Agent.logger.warn("Custom attribute key '#{key}' was longer than limit of #{KEY_LIMIT}. This attribute will be dropped.")
            return
          end

          if needs_length_limit?(value)
            value = value[0, VALUE_LIMIT]
          end

          super
        end

        def needs_length_limit?(value)
          if value.is_a?(String) || value.is_a?(Symbol)
            value.length > VALUE_LIMIT
          else
            false
          end
        end

      end
    end
  end
end
