# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'transaction_ignoring_test_cases'

class TransactionIgnoringTest < Minitest::Test
  include MultiverseHelpers
  include TransactionIgnoringTestCases

  def trigger_transaction(txn_name)
    TestWidget.new.run_transaction(txn_name)
  end

  def trigger_transaction_with_error(txn_name, error_msg)
    TestWidget.new.run_transaction(txn_name) do
      NewRelic::Agent.notice_error(error_msg)
    end
  end

  def trigger_transaction_with_slow_sql(txn_name)
    TestWidget.new.run_transaction(txn_name) do
      state = NewRelic::Agent::Tracer.state
      NewRelic::Agent.instance.sql_sampler.notice_sql("select * from test",
        "Database/test/select",
        nil, 1.5, state)
    end
  end

  class TestWidget
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def run_transaction(txn_name)
      NewRelic::Agent.set_transaction_name(txn_name)
      yield if block_given?
    end

    add_transaction_tracer :run_transaction
  end
end
