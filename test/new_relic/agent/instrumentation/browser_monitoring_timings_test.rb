# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

module NewRelic::Agent::Instrumentation
  class BrowserMonitoringTimingsTest < Test::Unit::TestCase

    def setup
      Time.stubs(:now).returns(Time.at(2000))
      @transaction = stub(
        :transaction_name => "Name",
        :start_time => 0
      )
    end

    def test_queue_time_in_millis
      t = BrowserMonitoringTimings.new(1000.1234, @transaction)
      assert_equal 1_000_123, t.queue_time_in_millis
    end

    def test_queue_time_in_seconds
      t = BrowserMonitoringTimings.new(1000.1234, @transaction)
      assert_equal 1_000.1234, t.queue_time_in_seconds
    end

    def test_queue_time_clamps_to_positive
      t = BrowserMonitoringTimings.new(-1000, @transaction)
      assert_equal 0, t.queue_time_in_millis
    end

    def test_queue_time_clamps_to_positive_in_seconds
      t = BrowserMonitoringTimings.new(-1000, @transaction)
      assert_equal 0, t.queue_time_in_seconds
    end

    def test_app_time_in_millis
      t = BrowserMonitoringTimings.new(nil, @transaction)
      assert_equal 2_000_000, t.app_time_in_millis
    end

    def test_app_time_in_seconds
      t = BrowserMonitoringTimings.new(nil, @transaction)
      assert_equal 2_000, t.app_time_in_seconds
    end

    def test_locks_time_at_instantiation
      t = BrowserMonitoringTimings.new(1000, @transaction)
      original = t.app_time_in_seconds

      Time.stubs(:now).returns(Time.at(3000))
      later = t.app_time_in_seconds

      assert_equal original, later
    end

    def test_transaction_name
      t = BrowserMonitoringTimings.new(nil, @transaction)
      assert_equal "Name", t.transaction_name
    end

    def test_defaults_to_transaction_info
      t = BrowserMonitoringTimings.new(1000, nil)
      assert_equal nil, t.transaction_name
      assert_equal 0.0, t.start_time_in_millis
    end

  end
end
