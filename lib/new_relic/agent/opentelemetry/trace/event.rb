# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        # stored on the span as events: [] (same as links)
        # should be sent as span.id
        # should be sent as trace.id
        # intrinsice attributes: type: SpanEvent, timestamp, span.id, trace.id, name
        # user attributes: anythign in the attributes key
        SpanEvent = Struct.new(:name, :attributes, :timestamp, :span_id, :trace_id)
        end
      end
    end
  end
end