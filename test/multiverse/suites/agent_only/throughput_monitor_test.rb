# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


module NewRelic
  module Agent
    class ThroughputMonitorTest < Minitest::Test

      include MultiverseHelpers

      setup_and_teardown_agent do
        NewRelic::Agent.config.add_config_for_testing :'distributed_tracing.enabled' => true
        #hard reset on the throughput monitor
        NewRelic::Agent.instance.instance_variable_set :@throughput_monitor, ThroughputMonitor.new
      end

      def test_throughput_monitor_valid_stats_and_reset_after_harvest
        sampled_count = 0
        20.times do |i|
          in_transaction("test_txn_#{i}") do |txn|
            sampled_count += 1 if txn.sampled?
          end
        end

        stats = NewRelic::Agent.instance.throughput_monitor.stats
        assert_equal 0, stats[:seen_last]
        assert_equal 20, stats[:seen]
        assert_equal sampled_count, stats[:sampled_count]

        run_harvest

        stats = NewRelic::Agent.instance.throughput_monitor.stats
        assert_equal 0, stats[:seen]
        assert_equal 20, stats[:seen_last]
      end
    end
  end
end
