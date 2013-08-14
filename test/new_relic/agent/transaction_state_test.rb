# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction_state'

module NewRelic::Agent
  class TransactionStateTest < Test::Unit::TestCase
    attr_reader :state

    def setup
      @state = TransactionState.new
    end

    def test_without_transaction_stack_on_thread
      state.current_transaction_stack = nil
      assert_equal false, state.in_background_transaction?
      assert_equal false, state.in_request_transaction?
    end

    def test_in_background_transaction
      state.current_transaction_stack = [NewRelic::Agent::Transaction.new]

      assert state.in_background_transaction?
    end

    def test_in_request_tranasction
      transaction = NewRelic::Agent::Transaction.new
      transaction.request = stub()

      state.current_transaction_stack = [transaction]

      assert state.in_request_transaction?
    end

    def test_in_request_transaction_checks_last
      earlier_transaction = NewRelic::Agent::Transaction.new
      transaction = NewRelic::Agent::Transaction.new
      transaction.request = stub()

      state.current_transaction_stack = [earlier_transaction, transaction]

      assert state.in_request_transaction?
    end
  end
end
