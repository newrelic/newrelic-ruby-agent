# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require './app'
require 'transaction_ignoring_test_cases'

class TransactionIgnorerController < ApplicationController
  def run_transaction
    state = NewRelic::Agent::Tracer.state
    NewRelic::Agent.set_transaction_name(params[:txn_name])
    NewRelic::Agent.notice_error(params[:error_msg]) if params[:error_msg]
    if params[:slow_sql]
      segment = NewRelic::Agent::Tracer.start_datastore_segment
      NewRelic::Agent::Datastores.notice_sql('select * from test')
      segment.finish
    end
    render(body: 'some stuff')
  end
end

class TransactionIgnoringTest < ActionDispatch::IntegrationTest
  include MultiverseHelpers
  include TransactionIgnoringTestCases

  def trigger_transaction(txn_name)
    get('/transaction_ignorer/run_transaction',
      params: {
        txn_name: txn_name
      })
  end

  def trigger_transaction_with_error(txn_name, error_msg)
    get('/transaction_ignorer/run_transaction',
      params: {
        txn_name: txn_name,
        error_msg: error_msg
      })
  end

  def trigger_transaction_with_slow_sql(txn_name)
    get('/transaction_ignorer/run_transaction',
      params: {
        txn_name: txn_name,
        slow_sql: 'true'
      })
  end
end
