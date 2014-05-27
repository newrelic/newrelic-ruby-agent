# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction_timings'

module NewRelic::Agent
  class TransactionTimingsTest < Minitest::Test

    def setup
      @start_time = freeze_time
      @name = "Name"
    end

    def test_transaction_name
      t = TransactionTimings.new(nil, nil, @name)
      assert_equal "Name", t.transaction_name
    end

    def test_transaction_name_or_unknown
      t = TransactionTimings.new(nil, nil, @name)
      assert_equal "Name", t.transaction_name_or_unknown
    end

    def test_transaction_name_or_unknown_when_nil
      t = TransactionTimings.new(nil, nil, nil)
      assert_equal "(unknown)", t.transaction_name_or_unknown
    end

    def test_queue_time_nil
      t = TransactionTimings.new(nil, @start_time, @name)
      assert_equal 0.0, t.queue_time_in_millis
    end

    def test_queue_time_in_millis
      t = TransactionTimings.new(1000.1234, @start_time, @name)
      assert_equal 1_000_123, t.queue_time_in_millis
    end

    def test_queue_time_in_seconds
      t = TransactionTimings.new(1000.1234, @start_time, @name)
      assert_equal 1_000.1234, t.queue_time_in_seconds
    end

    def test_queue_time_clamps_to_positive_in_millis
      t = TransactionTimings.new(-1000, @start_time, @name)
      assert_equal 0, t.queue_time_in_millis
    end

    def test_queue_time_clamps_to_positive_in_seconds
      t = TransactionTimings.new(-1000, @start_time, @name)
      assert_equal 0, t.queue_time_in_seconds
    end

    def test_screwy_queue_time_defaults_to_zero
      t = TransactionTimings.new("a duck", @start_time, @name)
      assert_equal 0.0, t.queue_time_in_seconds
    end

    def test_app_time_in_millis
      advance_time(2)
      t = TransactionTimings.new(nil, @start_time, @name)
      assert_equal 2_000.0, t.app_time_in_millis
    end

    def test_app_time_in_seconds
      advance_time(2)
      t = TransactionTimings.new(nil, @start_time, @name)
      assert_equal 2.0, t.app_time_in_seconds
    end

    def test_locks_time_at_instantiation
      t = TransactionTimings.new(1000, @start_time, @name)
      original = t.app_time_in_seconds

      advance_time(3)
      later = t.app_time_in_seconds

      assert_equal original, later
    end

    def test_clamp_to_positive
      t = TransactionTimings.new(nil, nil, nil)
      assert_equal(0.0, t.clamp_to_positive(-1), "should clamp a negative value to zero")
      assert_equal(1232, t.clamp_to_positive(1232), "should pass through the value when it is positive")
      assert_equal(0, t.clamp_to_positive(0), "should not mess with zero when passing it through")
    end

  end
end
