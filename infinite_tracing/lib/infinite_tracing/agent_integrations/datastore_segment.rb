# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Transaction
      class DatastoreSegment
        def record_span_event
          tracer = ::NewRelic::Agent.agent.infinite_tracer
          tracer << Proc.new { SpanEventPrimitive.for_datastore_segment self }
        end
      end
    end
  end
end
