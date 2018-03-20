# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/adaptive_sampler'

module NewRelic
  module Agent
    class AdaptiveSamplerTest < Minitest::Test
      def test_adaptive_sampler
        nr_freeze_time
        sampler = AdaptiveSampler.new
        10000.times { sampler.sampled? }
        stats = sampler.stats
        assert_equal 10, stats[:sampled_count]
        assert_equal 10000, stats[:seen]
        advance_time(60)
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
        advance_time(120)
        10001.times { sampler.sampled? }
        stats = sampler.stats
        assert_equal 0, stats[:seen_last]
        assert_equal 10001, stats[:seen]
      end
    end
  end
end
