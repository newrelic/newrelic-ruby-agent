# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


module NewRelic
  module Agent
    class AdaptiveSamplerTest < Minitest::Test

      include MultiverseHelpers

      setup_and_teardown_agent do
        NewRelic::Agent.config.add_config_for_testing :'distributed_tracing.enabled' => true
        #hard reset on the adaptive_sampler
        NewRelic::Agent.instance.instance_variable_set :@adaptive_sampler, AdaptiveSampler.new
      end

      def test_adaptive_sampler_valid_stats_and_reset_after_harvest
        nr_freeze_time

        sampled_count = 0
        20.times do |i|
          in_transaction("test_txn_#{i}") do |txn|
            sampled_count += 1 if txn.sampled?
          end
        end

        stats = NewRelic::Agent.instance.adaptive_sampler.stats
        assert_equal 0, stats[:seen_last]
        assert_equal 20, stats[:seen]
        assert_equal sampled_count, stats[:sampled_count]

        advance_time(60)

        in_transaction("test_txn_20") {}

        stats = NewRelic::Agent.instance.adaptive_sampler.stats
        assert_equal 1, stats[:seen]
        assert_equal 20, stats[:seen_last]
      end
    end
  end
end
