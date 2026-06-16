# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module SpanEventPrimitivePatch
        # span kind is already added in for_external_request_segment
        # and in for_datastore_segment, so this just covers the other cases
        def for_segment(segment)
          span_data = super
          attach_span_kind(span_data, segment)
        end

        private

        def get_span_kind(span_data, segment)
          if segment.instance_variable_defined?(:@otel_span)
            otel_span = segment.instance_variable_get(:@otel_span)
            kind = otel_span.kind&.to_s
            span_data[0][SpanEventPrimitive::SPAN_KIND_KEY] = kind if kind

            span_data
          end
        end
      end
    end
  end
end
