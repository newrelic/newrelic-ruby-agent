# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This agent is loaded by the plug when the plug-in is disabled
# It recreates just enough of the API to not break any clients that
# invoke the Agent.
module NewRelic
  module Agent
    class ShimAgent < NewRelic::Agent::Agent
      def self.instance
        @instance ||= self.new
      end

      def initialize
        super
        @stats_engine.extend NewRelic::Agent::StatsEngine::Shim
        @transaction_sampler.extend NewRelic::Agent::TransactionSampler::Shim
        @sql_sampler.extend NewRelic::Agent::SqlSampler::Shim
        @error_collector.extend NewRelic::Agent::ErrorCollector::Shim
      end

      def after_fork *args; end
      def start *args; end
      def shutdown *args; end
      def merge_data_for_endpoint *args; end
      def push_trace_execution_flag *args; end
      def pop_trace_execution_flag *args; end
      def browser_timing_header; "" end
      def browser_timing_footer; "" end
    end
  end
end
