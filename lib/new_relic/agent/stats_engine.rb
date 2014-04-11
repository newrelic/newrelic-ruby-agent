# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/stats_engine/metric_stats'
require 'new_relic/agent/stats_engine/samplers'
require 'new_relic/agent/stats_engine/gc_profiler'
require 'new_relic/agent/stats_engine/stats_hash'

module NewRelic
  module Agent
    # This class handles all the statistics gathering for the agent
    class StatsEngine
      include MetricStats
      include Samplers

      attr_accessor :metric_rules

      def initialize
        @stats_lock   = Mutex.new
        @stats_hash   = StatsHash.new
        @metric_rules = RulesEngine.new
      end

      # All access to the @stats_hash ivar should be funnelled through this
      # method to ensure thread-safety.
      def with_stats_lock
        @stats_lock.synchronize { yield }
      end
    end
  end
end
