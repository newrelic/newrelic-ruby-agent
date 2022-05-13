# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'
require 'new_relic/agent/adaptive_sampler'

module NewRelic
  module Agent
    class AdaptiveSamplerTest < Minitest::Test
      def test_adaptive_sampler
        nr_freeze_process_time
        sampler = AdaptiveSampler.new
        10000.times { sampler.sampled? }
        stats = sampler.stats
        assert_equal 10, stats[:sampled_count]
        assert_equal 10000, stats[:seen]
        advance_process_time(60)
        10001.times { sampler.sampled? }
        stats = sampler.stats
        assert_equal 10000, stats[:seen_last]
        assert_equal 10001, stats[:seen]
      end

      def test_stats_accurate_when_interval_skipped
        sampler = AdaptiveSampler.new
        10000.times { sampler.sampled? }
        stats = sampler.stats
        assert_equal 10, stats[:sampled_count]
        assert_equal 10000, stats[:seen]
        advance_process_time(120)
        10001.times { sampler.sampled? }
        stats = sampler.stats
        assert_equal 0, stats[:seen_last]
        assert_equal 10001, stats[:seen]
      end

      def test_sampling_target_updated_when_config_changes
        with_config sampling_target: 55 do
          sampler = NewRelic::Agent.instance.adaptive_sampler
          target = sampler.instance_variable_get :@target

          assert_equal 55, target
        end
      end

      def test_sampling_period_updated_when_config_changes
        with_config sampling_target_period_in_seconds: 500 do
          sampler = NewRelic::Agent.instance.adaptive_sampler
          period = sampler.instance_variable_get :@period_duration

          assert_equal 500, period
        end
      end

      def test_exponential_backoff_can_be_nonzero_value
        sampler = NewRelic::Agent.instance.adaptive_sampler
        # 19 is the mathematical maximum for a nonzero value for the default @target = 10
        sampler.instance_variable_set(:@sampled_count, 19)
        result = sampler.exponential_backoff
        assert result > 0, 'Exponential backoff value was not greater than zero'
      end
    end
  end
end
