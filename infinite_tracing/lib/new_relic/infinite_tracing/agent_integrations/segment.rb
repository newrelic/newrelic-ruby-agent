# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
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
          tracer << Proc.new { SpanEventPrimitive.for_segment self }
        end
      end
    end
  end
end
