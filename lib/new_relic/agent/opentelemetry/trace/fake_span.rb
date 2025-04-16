# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# TODO: do we want to nest everything within a Trace namespace?
module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        # TODO: Should this inherit from the OpenTelemetry API like the SDK does?
        class FakeSpan #  < ::OpenTelemetry::Trace::Span
          attr_reader :context

          def initialize(segment:, transaction:)
            @context = ::OpenTelemetry::Trace::SpanContext.new(
              trace_id: transaction.trace_id,
              span_id: segment.guid,
              trace_flags: 1
            )
          end

          def record_exception(exception, attributes: nil)
            # TODO: test this
            # TODO: Consider removing it from the first PR
            if attributes.nil?
              NewRelic::Agent.notice_error(exception)
            else
              NewRelic::Agent.notice_error(exception, {custom_params: attributes})
            end
          end

          def set_attribute(key, value)
            # TODO: test this
            # TODO: Consider removing it from the first issue
            NewRelic::Agent.add_custom_span_attributes({key => value})
          end
        end
      end
    end
  end
end
