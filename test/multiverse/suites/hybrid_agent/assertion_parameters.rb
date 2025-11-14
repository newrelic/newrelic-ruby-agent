# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module AssertionParameters
  def current_otel_span
    return nil if OpenTelemetry::Trace.current_span == OpenTelemetry::Trace::Span::INVALID

    OpenTelemetry::Trace.current_span
  end

  def current_otel_span_context
    current_otel_span&.context
  end

  def current_transaction
    NewRelic::Agent::Tracer.current_transaction
  end

  def injected
    injected = {}
    split_headers = @headers['traceparent'].split('-')
    injected['trace_id'] = split_headers[1]
    injected['span_id'] = split_headers[2]
    injected['sampled'] = split_headers[3] == '01'

    injected
  end
end
