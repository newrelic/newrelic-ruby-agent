# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm' unless defined?( NewRelic )
require 'new_relic/agent' unless defined?( NewRelic::Agent )
require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/priority_sampled_buffer'

module NewRelic
  module Agent
    class SpanEventAggregator < EventAggregator

      named :SpanEventAggregator
      capacity_key :'span_events.max_samples_stored'
      enabled_key :'span_events.enabled'
      buffer_class PrioritySampledBuffer

      def record priority: nil, event:nil, &blk
        unless(event || priority && blk)
          raise ArgumentError, "Expected priority and block, or event"
        end

        return unless enabled?

        @lock.synchronize do
          @buffer.append priority: priority, event: event, &blk
          notify_if_full
        end
      end
    end
  end
end
