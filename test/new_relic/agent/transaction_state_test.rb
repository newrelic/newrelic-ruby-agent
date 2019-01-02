# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/transaction_state'

module NewRelic::Agent
  class TransactionStateTest < Minitest::Test
    attr_reader :state

    def setup
      TransactionState.tl_clear
      @state = Tracer.state
    end

    def teardown
      TransactionState.tl_clear
    end

    def test_in_background_transaction
      in_transaction(:category => :task) do |txn|
        assert !txn.recording_web_transaction?
      end
    end

    def test_in_request_tranasction
      in_web_transaction do |txn|
        assert txn.recording_web_transaction?
      end
    end

    def test_reset_doesnt_touch_record_sql
      state.record_sql = false
      state.reset
      refute state.record_sql
    end

    def test_reset_doesnt_touch_untraced_stack
      state.push_traced(true)
      state.reset
      assert_equal [true], state.untraced
    end

    def test_reset_touches_everything!
      state.sql_sampler_transaction_data = Object.new
      state.push_traced(true)

      state.reset

      # Anything in this list should be tested explicitly by itself!
      skip_checking = [:@traced_method_stack, :@record_sql, :@untraced]
      variables = state.instance_variables.map(&:to_sym) - skip_checking

      variables.each do |ivar|
        value = state.instance_variable_get(ivar)
        assert [0, nil, false, []].include?(value),
               "Expected #{ivar} to reset, but was #{value}"
      end
    end
  end
end
