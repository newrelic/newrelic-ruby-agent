# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_trace_metrics'

module NewRelic
  module Agent
    class DistributedTraceMetricsTest < Minitest::Test


      def test_transport_duration_returned_in_seconds_when_positive
        duration = 2.0
        parent_timestamp, txn_start = make_timestamps duration
        txn = stub(start_time: txn_start)
        payload = stub(timestamp: parent_timestamp)

        assert_equal \
          duration,
          DistributedTraceMetrics.transport_duration(txn, payload).round(0)
      end

      def test_transport_duration_zero_with_clock_skew
        duration = -1.0
        parent_timestamp, txn_start = make_timestamps duration
        txn = stub(start_time: txn_start)
        payload = stub(timestamp: parent_timestamp)

        assert_equal 0, DistributedTraceMetrics.transport_duration(txn, payload)
      end

      def make_timestamps duration
        transaction_start = Time.now()
        parent_timestamp = ((transaction_start.to_f - duration) * 1000).round

        return parent_timestamp, transaction_start
      end
    end
  end
end

