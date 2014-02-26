# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_state'

module NewRelic
  module Rack
    module TransactionReset
      RESET_KEY = "newrelic.transaction_reset".freeze

      def ensure_transaction_reset(env)
        return if env.has_key?(RESET_KEY)

        NewRelic::Agent::TransactionState.reset
        env[RESET_KEY] = true
      end
    end
  end
end
