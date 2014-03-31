# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rails/test_help'
require './app'
require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')
require 'transaction_ignoring_test_cases'

class TransactionIgnorerController < ApplicationController
  include Rails.application.routes.url_helpers

  def run_transaction
    render :text => 'some stuff'
  end

  def run_transaction_with_error
    ????
  end

end

class TransactionIgnoringTest < ActionDispatch::IntegrationTest

  include MultiverseHelpers
  include TransactionIgnoringTestCases

  def trigger_transaction(name)
    get '/transaction_ignorer/run_transaction'
  end

  def trigger_transaction_with_error(txn_name, error_msg)
    get '/transaction_ignorer/run_transaction_with_error' ????
  end

end
