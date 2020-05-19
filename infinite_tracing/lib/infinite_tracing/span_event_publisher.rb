# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  class Transaction
    DatastoreSegment.class_eval do
      def record_span_event
        InfiniteTracing::Client << self
        # aggregator = ::NewRelic::Agent.agent.span_event_aggregator
        # priority   = transaction.priority

        # aggregator.record(priority: priority) do
        #   SpanEventPrimitive.for_datastore_segment(self)
        # end
      end
    end
  end
end
