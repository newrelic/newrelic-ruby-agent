# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/transaction/throughput_monitor'

module NewRelic
  module Agent
    class Transaction
      class ThroughputMonitorTest < Minitest::Test
        def test_throughput
          monitor = ThroughputMonitor.new 10
          10000.times { monitor.collect_sample? }
          stats = monitor.stats
          assert_equal 10, stats[:sampled_count]
          assert_equal 10000, stats[:seen]
          monitor.reset
          10001.times { monitor.collect_sample? }
          stats = monitor.stats
          assert_equal 10000, stats[:seen_last]
          assert_equal 10001, stats[:seen]
        end
      end
    end
  end
end
