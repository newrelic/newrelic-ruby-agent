# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Transaction
      class Segment
        def segment_complete
          record_span_event
        end

        def record_span_event
          tracer = ::NewRelic::Agent.agent.infinite_tracer
          tracer << proc { SpanEventPrimitive.for_segment self }
        end
      end
    end
  end
end
