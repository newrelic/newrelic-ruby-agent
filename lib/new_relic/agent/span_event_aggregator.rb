# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'newrelic_rpm' unless defined?(NewRelic)
require 'new_relic/agent' unless defined?(NewRelic::Agent)
require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/priority_sampled_buffer'

module NewRelic
  module Agent
    class SpanEventAggregator < EventAggregator
      named :SpanEventAggregator
      capacity_key :'span_events.max_samples_stored'

      enabled_keys :'span_events.enabled',
        :'distributed_tracing.enabled'

      def record(priority: nil, event: nil, &blk)
        unless event || priority && blk
          raise ArgumentError, 'Expected priority and block, or event'
        end

        return unless enabled?

        @lock.synchronize do
          @buffer.append(priority: priority, event: event, &blk)
          notify_if_full
        end
      end

      SUPPORTABILITY_TOTAL_SEEN = 'Supportability/SpanEvent/TotalEventsSeen'.freeze
      SUPPORTABILITY_TOTAL_SENT = 'Supportability/SpanEvent/TotalEventsSent'.freeze
      SUPPORTABILITY_DISCARDED = 'Supportability/SpanEvent/Discarded'.freeze

      def harvest!
        metadata, events = super
        span_links = []
        events.each do |event|
          # Span events are normally [intrinsics, custom_attrs, agent_attrs].
          # When a span has links, a 4th element is appended:
          # [intrinsics, custom_attrs, agent_attrs, span_links]
          #
          # Span Links must be sent to the backend at the top level of the main
          # payload, not nested inside an individual Span. This pulls them out
          # be flattened into the final array: [Span, SpanLink, Span, SpanLink]
          span_links.concat(event.slice!(3)) if event.length > 3
        end
        [metadata, events.concat(span_links)]
      end

      def after_harvest(metadata)
        seen = metadata[:seen]
        sent = metadata[:captured]
        discarded = seen - sent

        ::NewRelic::Agent.record_metric(SUPPORTABILITY_TOTAL_SEEN, count: seen)
        ::NewRelic::Agent.record_metric(SUPPORTABILITY_TOTAL_SENT, count: sent)
        ::NewRelic::Agent.record_metric(SUPPORTABILITY_DISCARDED, count: discarded)

        super
      end
    end
  end
end
