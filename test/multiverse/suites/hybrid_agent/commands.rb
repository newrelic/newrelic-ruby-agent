# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Commands
  def do_work_in_span(span_name:, span_kind:, &block)
    @tracer.in_span(span_name, kind: span_kind) do
      yield if block
    end
  end

  def do_work_in_span_with_remote_parent(span_name:, span_kind:, &block)
    context = OpenTelemetry::Context.current
    span_context = OpenTelemetry::Trace::SpanContext.new(
      trace_id: 'ba8bc8cc6d062849b0efcf3c169afb5a',
      span_id: '6d3efb1b173fecfa',
      trace_flags: '01',
      remote: true
    )

    span = OpenTelemetry::Trace.non_recording_span(span_context)
    parent_context = OpenTelemetry::Trace.context_with_span(span, parent_context: context)

    span = @tracer.start_span(span_name, with_parent: parent_context, kind: span_kind)
    yield if block
    span.finish
  end

  def do_work_in_span_with_inbound_context(span_name:, span_kind:, trace_id_in_header:,
    span_id_in_header:, sampled_flag_in_header:, &block)
    # TODO
    yield if block
  end

  def do_work_in_transaction(transaction_name:, &block)
    NewRelic::Agent::Tracer.in_transaction(name: transaction_name, category: :web) do
      yield if block
    end
  end

  def do_work_in_segment(segment_name:, &block)
    segment = NewRelic::Agent::Tracer.start_segment(name: segment_name)
    yield if block
  ensure
    segment&.finish
  end

  def add_otel_attribute(name:, value:, &block)
    OpenTelemetry::Trace.current_span&.set_attribute(name, value)
    yield if block
  end

  def record_exception_on_span(error_message:, &block)
    exception = StandardError.new(error_message)
    OpenTelemetry::Trace.current_span.record_exception(exception)
    yield if block
  end

  def simulate_external_call(url:, &block)
    # TODO
    yield if block
  end

  def o_tel_inject_headers(&block)
    # TODO: figure out how to pass the request
    request = {}
    OpenTelemetry.propagation.inject(request)
    yield if block
  end

  def nr_inject_headers(&block)
    # TODO: figure out how to get the headers
    headers = {}
    NewRelic::Agent::DistributedTracing.insert_distributed_trace_headers(headers)
    yield if block
  end
end
