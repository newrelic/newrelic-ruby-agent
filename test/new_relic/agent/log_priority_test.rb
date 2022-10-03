# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

require 'new_relic/agent/log_priority'

module NewRelic::Agent
  class LogPriorityTest < Minitest::Test
    def test_uses_transaction_if_its_there
      in_transaction do |txn|
        assert_equal txn.priority, LogPriority.priority_for(txn)
      end
    end

    def test_random_value_if_no_transaction
      LogPriority.stubs(:rand).returns(0.1)
      assert_equal 0.1, LogPriority.priority_for(nil)
    end
  end
end
