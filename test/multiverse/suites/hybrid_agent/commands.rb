# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Commands
  def do_work_in_span(span_name:, span_kind:, &block)
    span = @tracer.start_span(span_name, kind: span_kind)
    yield if block
  ensure
    span&.finish
  end

  def do_work_in_span_with_remote_parent(span_name:, span_kind:, &block)
    span = @tracer.start_span(span_name, kind: span_kind)
    span.context.instance_variable_set(:@remote, true)
    yield if block
  ensure
    span&.finish
  end

  def do_work_in_transaction(transaction_name:, &block)
    transaction = NewRelic::Agent::Tracer.start_transaction(name: transaction_name, category: :web)
    yield if block
  ensure
    transaction&.finish
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

  def o_tel_inject_headers
    # TODO
    yield if block_given?
  end

  def nr_inject_headers(&block)
    # TODO
    yield if block
  end
end
