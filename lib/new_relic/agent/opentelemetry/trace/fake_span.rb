# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class FakeSpan < ::OpenTelemetry::Trace::Span
          attr_reader :context

          def initialize(segment:, transaction:)
            @context = ::OpenTelemetry::Trace::SpanContext.new(
              trace_id: transaction.trace_id,
              span_id: segment.guid,
              trace_flags: 1
            )
          end
        end
      end
    end
  end
end
