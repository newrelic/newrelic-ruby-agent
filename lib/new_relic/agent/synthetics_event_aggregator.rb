# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/synthetics_event_buffer'

module NewRelic
  module Agent
    class SyntheticsEventAggregator
      def initialize
        @notified_full = false
        @lock = Mutex.new
        @samples = SyntheticsEventBuffer.new(Agent.config[:'synthetics.events_limit'])
        register_config_callbacks
      end

      def enabled?
        NewRelic::Agent.config[:'analytics_events.enabled']
      end

      def reset!
        @lock.synchronize do
          @samples.reset!
        end
      end

      def harvest!
        num_dropped = 0
        metadata, samples = nil, nil
        @lock.synchronize do
          num_dropped = @samples.num_dropped
          samples = @samples.to_a
          metadata = reservoir_metadata
          @samples.reset!
          @notified_full = false
        end
        record_dropped_synthetics(num_dropped)
        [metadata, samples]
      end

      def merge! payload
        _, events = payload
        @lock.synchronize do
          events.each { |e| @samples.append_with_reject e}
        end
      end

      def append_or_reject event
        return unless enabled?
        result = nil
        @lock.synchronize do
          result = @samples.append_with_reject event.to_collector_array
        end
        result
      end

      def has_metadata?
        true
      end

      private

      def reservoir_metadata
        {
          :reservoir_size => NewRelic::Agent.config[:'synthetics.events_limit'],
          :events_seen => @samples.num_seen
        }
      end

      def record_dropped_synthetics(synthetics_dropped)
        return unless synthetics_dropped > 0

        NewRelic::Agent.logger.debug("Synthetics transaction event limit (#{@samples.capacity}) reached. Further synthetics events this harvest period dropped.")

        engine = NewRelic::Agent.instance.stats_engine
        engine.tl_record_supportability_metric_count("SyntheticsEventAggregator/synthetics_events_dropped", synthetics_dropped)
      end

      def register_config_callbacks
        NewRelic::Agent.config.register_callback(:'synthetics.events_limit') do |max_samples|
          NewRelic::Agent.logger.debug "SyntheticsEventAggregator limit for events set to #{max_samples}"
          @lock.synchronize { @samples.capacity = max_samples }
        end
      end
    end
  end
end

