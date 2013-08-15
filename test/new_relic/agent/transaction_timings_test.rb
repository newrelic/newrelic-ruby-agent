# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction_timings'

module NewRelic::Agent
  class TransactionTimingsTest < Test::Unit::TestCase

    def setup
      Time.stubs(:now).returns(Time.at(2000))

      @transaction = NewRelic::Agent::TransactionState.new
      @transaction.transaction = stub(:name => "Name", :start_time => 0)
    end

    def test_queue_time_nil
      t = TransactionTimings.new(nil, @transaction)
      assert_equal 0.0, t.queue_time_in_millis
    end

    def test_queue_time_in_millis
      t = TransactionTimings.new(1000.1234, @transaction)
      assert_equal 1_000_123, t.queue_time_in_millis
    end

    def test_queue_time_in_seconds
      t = TransactionTimings.new(1000.1234, @transaction)
      assert_equal 1_000.1234, t.queue_time_in_seconds
    end

    def test_queue_time_clamps_to_positive_in_millis
      t = TransactionTimings.new(-1000, @transaction)
      assert_equal 0, t.queue_time_in_millis
    end

    def test_queue_time_clamps_to_positive_in_seconds
      t = TransactionTimings.new(-1000, @transaction)
      assert_equal 0, t.queue_time_in_seconds
    end

    def test_screwy_queue_time_defaults_to_zero
      t = TransactionTimings.new("a duck", @transaction)
      assert_equal 0.0, t.queue_time_in_seconds
    end

    def test_app_time_in_millis
      t = TransactionTimings.new(nil, @transaction)
      assert_equal 2_000_000, t.app_time_in_millis
    end

    def test_app_time_in_seconds
      t = TransactionTimings.new(nil, @transaction)
      assert_equal 2_000, t.app_time_in_seconds
    end

    def test_locks_time_at_instantiation
      t = TransactionTimings.new(1000, @transaction)
      original = t.app_time_in_seconds

      Time.stubs(:now).returns(Time.at(3000))
      later = t.app_time_in_seconds

      assert_equal original, later
    end

    def test_transaction_name
      t = TransactionTimings.new(nil, @transaction)
      assert_equal "Name", t.transaction_name
    end

    def test_defaults_to_transaction_info
      t = TransactionTimings.new(1000, nil)
      assert_equal nil, t.transaction_name
      assert_equal 0.0, t.start_time_in_millis
    end

    # If (for example) an action is ignored, we might still look for the
    # timings for things like CAT
    def test_without_transaction_in_state
      @transaction.transaction = nil
      t = TransactionTimings.new(1000, @transaction)

      assert_nil t.transaction_name
      assert_equal 1_000, t.queue_time_in_seconds
    end

    def test_clamp_to_positive
      t = TransactionTimings.new(nil, nil)
      assert_equal(0.0, t.clamp_to_positive(-1), "should clamp a negative value to zero")
      assert_equal(1232, t.clamp_to_positive(1232), "should pass through the value when it is positive")
      assert_equal(0, t.clamp_to_positive(0), "should not mess with zero when passing it through")
    end

  end
end
