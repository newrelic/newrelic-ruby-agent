# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'
require 'transaction_ignoring_test_cases'

class TransactionIgnorerController < ApplicationController
  def run_transaction
    state = NewRelic::Agent::TransactionState.tl_get
    NewRelic::Agent.set_transaction_name(params[:txn_name])
    NewRelic::Agent.notice_error(params[:error_msg]) if params[:error_msg]
    NewRelic::Agent.instance.sql_sampler.notice_sql("select * from test",
                                 "Database/test/select",
                                 nil, 1.5, state) if params[:slow_sql]
    render :text => 'some stuff'
  end


end

class TransactionIgnoringTest < RailsMultiverseTest

  include MultiverseHelpers
  include TransactionIgnoringTestCases

  def trigger_transaction(txn_name)
    get '/transaction_ignorer/run_transaction', :txn_name  => txn_name
  end

  def trigger_transaction_with_error(txn_name, error_msg)
    get '/transaction_ignorer/run_transaction', :txn_name  => txn_name,
                                                :error_msg => error_msg
  end

  def trigger_transaction_with_slow_sql(txn_name)
    get '/transaction_ignorer/run_transaction', :txn_name  => txn_name,
                                                :slow_sql  => 'true'
  end

end
