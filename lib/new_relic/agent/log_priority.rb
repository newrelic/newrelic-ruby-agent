# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/event_aggregator'

# Stateless calculation of priority for a given log event
module NewRelic
  module Agent
    module LogPriority
      extend self

      SEVERITIES = Logger::Severity.constants.inject({}) do |memo, sev|
        memo[sev.to_s] = Logger::Severity.const_get(sev)
        memo
      end

      TRANSACTION_BONUS = 10
      TRANSACTION_ERROR_BONUS = 10
      TRANSACTION_SAMPLE_BONUS = 100

      def priority_for(severity, txn = nil)
        priority = SEVERITIES[severity.to_s] || 0
        priority += TRANSACTION_BONUS if txn
        priority += TRANSACTION_ERROR_BONUS if txn && txn.payload && txn.payload[:error]
        priority += TRANSACTION_SAMPLE_BONUS if txn && txn.sampled?
        priority
      end
    end
  end
end
