# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/tracer'

module NewRelic::Agent
  class TracerStateTest < Minitest::Test
    attr_reader :state

    def setup
      Tracer.clear_state
      @state = Tracer.state
    end

    def teardown
      Tracer.clear_state
    end

    def test_in_background_transaction
      in_transaction(:category => :task) do |txn|
        refute txn.recording_web_transaction?
      end
    end

    def test_in_request_transaction
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
        empties = [0, nil, false, []]
        assert_includes(empties, value, "Expected #{ivar} to reset, but was #{value}")
      end
    end
  end
end
