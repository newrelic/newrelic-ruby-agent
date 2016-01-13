# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/synthetics_event_buffer'

module NewRelic
  module Agent
    class SyntheticsEventAggregator < EventAggregator

      named :SyntheticsEventAggregator
      capacity_key :'synthetics.events_limit'
      enabled_key :'analytics_events.enabled'
      buffer_class SyntheticsEventBuffer

      def append_or_reject event
        return unless enabled?

        @lock.synchronize do
          @buffer.append_with_reject event
        end
      end

      # slightly different semantics than the EventAggregator for merge
      def merge! payload
        _, events = payload
        @lock.synchronize do
          events.each { |e| @buffer.append_with_reject e}
        end
      end

      private

      def after_harvest metadata
        record_dropped_synthetics metadata
      end

      def record_dropped_synthetics metadata
        num_dropped = metadata[:seen] - metadata[:captured]
        return unless num_dropped > 0

        NewRelic::Agent.logger.debug("Synthetics transaction event limit (#{metadata[:capacity]}) reached. Further synthetics events this harvest period dropped.")

        engine = NewRelic::Agent.instance.stats_engine
        engine.tl_record_supportability_metric_count("SyntheticsEventAggregator/synthetics_events_dropped", num_dropped)
      end
    end
  end
end

