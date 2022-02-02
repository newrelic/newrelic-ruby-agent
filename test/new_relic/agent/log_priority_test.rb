# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

require 'new_relic/agent/log_priority'

module NewRelic::Agent
  class LogPriorityTest < Minitest::Test
    def test_severities_only
      assert_equal 0, LogPriority.priority_for("DEBUG")
      assert_equal 1, LogPriority.priority_for("INFO")
      assert_equal 2, LogPriority.priority_for("WARN")
      assert_equal 3, LogPriority.priority_for("ERROR")
      assert_equal 4, LogPriority.priority_for("FATAL")
      assert_equal 5, LogPriority.priority_for("UNKNOWN")

      assert_equal 0, LogPriority.priority_for("BUNK")
      assert_equal 0, LogPriority.priority_for(nil)
    end

    def test_severity_in_transaction
      txn = in_transaction do |txn|
        txn.sampled = false
        assert_equal 11, LogPriority.priority_for("INFO", txn)
      end
    end

    def test_severity_in_error_transaction
      txn = in_transaction do |txn|
        txn.sampled = false
        txn.notice_error("Boo")
      end

      assert_equal 21, LogPriority.priority_for("INFO", txn)
    end

    def test_severity_in_sampled_transaction
      txn = in_transaction do |txn|
        txn.sampled = true
      end

      assert_equal 111, LogPriority.priority_for("INFO", txn)
    end
  end
end
