# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'opentelemetry'
require 'newrelic_rpm'

module NewRelicTestOperations
		# [Transaction]
		# public static void DoWorkInTransaction(string transactionName, Action work)
		# {
		# 	NewRelic.Api.Agent.NewRelic.SetTransactionName("Custom", transactionName);
		# 	work();
		# }
  def do_work_in_transaction(transaction_name, &work)
    NewRelic::Agent.set_transaction_name(transaction_name)
    yield
  end
end
