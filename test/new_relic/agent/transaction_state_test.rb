# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction_state'

module NewRelic::Agent
  class TransactionStateTest < MiniTest::Unit::TestCase
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

    def test_timings_without_transaction
      freeze_time

      state.reset(nil)
      timings = state.timings

      assert_equal 0.0, timings.queue_time_in_seconds
      assert_equal 0.0, timings.app_time_in_seconds
      assert_equal nil, timings.transaction_name
    end

    def test_timings_with_transaction
      earliest_time = freeze_time
      transaction = NewRelic::Agent::Transaction.new
      transaction.apdex_start = earliest_time
      transaction.start_time = earliest_time + 5
      transaction.name = "Transaction/name"
      state.transaction = transaction

      advance_time(10.0)
      timings = state.timings

      assert_equal 5.0, timings.queue_time_in_seconds
      assert_equal 5.0, timings.app_time_in_seconds
      assert_equal transaction.name, timings.transaction_name
    end

    GUID = "goo-id"

    def test_request_guid_to_include
      with_config(:apdex_t => 2.0) do
        freeze_time

        state.request_token = "token"
        state.request_guid = GUID
        state.transaction = NewRelic::Agent::Transaction.new

        advance_time(4.0)

        assert_equal GUID, state.request_guid_to_include
      end
    end

    def test_requst_guid_excluded_if_request_fast_enough
      with_config(:apdex_t => 2.0) do
        freeze_time

        state.request_token = "token"
        state.request_guid = GUID
        state.transaction = NewRelic::Agent::Transaction.new

        advance_time(1.0)

        assert_equal "", state.request_guid_to_include
      end
    end

    def test_request_guid_excluded_if_no_token
      with_config(:apdex_t => 2.0) do
        freeze_time

        state.request_token = nil
        state.request_guid = GUID
        state.transaction = NewRelic::Agent::Transaction.new

        advance_time(4.0)

        assert_equal "", state.request_guid_to_include
      end
    end
  end
end
