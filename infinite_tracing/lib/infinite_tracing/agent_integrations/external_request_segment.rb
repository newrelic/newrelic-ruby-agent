# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Transaction
      class ExternalRequestSegment
        def record_span_event
          # don't record a span event if the transaction is ignored
          return if transaction.ignore?

          tracer = ::NewRelic::Agent.agent.infinite_tracer
          tracer << proc { SpanEventPrimitive.for_external_request_segment(self) }
        end
      end
    end
  end
end
