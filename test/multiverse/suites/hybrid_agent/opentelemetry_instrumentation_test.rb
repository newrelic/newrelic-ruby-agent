# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true
require 'opentelemetry'

class HybridAgentTest < Minitest::Test
  def setup
    @tracer = OpenTelemetry.tracer_provider.tracer
  end

  def do_work_in_span(span_name:, span_kind:, &block)
    # we also have an in_span API, should that be used instead?
    span = @tracer.start_span(span_name, kind: span_kind)
    yield
  ensure
    span&.finish
  end

  def do_work_in_transaction(transaction_name:, &block)
    # we also have an in_transaction API, should that be used instead?
    transaction = NewRelic::Agent::Tracer.start_transaction(name: transaction_name, category: :web)
    yield
  ensure
    transaction&.finish
  end

  # what operations run in your work() funtion?

  def test_does_not_create_segment_without_a_transaction
    skip 'not yet implemented'
    do_work_in_span(span_name: "Bar", span_kind: "Internal") do
      puts 'hi'

      # the OpenTelemetry span should not be created (span invalid)
      assert_equal OpenTelemetry::Trace.current_span, OpenTelemetry::Trace::Span::INVALID

      # there should be no transaction
      assert_nil NewRelic::Agent::Tracer.current_transaction
    end

    transactions = harvest_transaction_events![1]
    spans = harvest_span_events![1]

    assert_empty transactions
    assert_empty spans
  end

  def test_creates_opentelemetry_segment_in_a_transaction
    skip 'not yet implemented'
    do_work_in_transaction(transaction_name: "Foo") do
      do_work_in_span(span_name: "Bar", span_kind: "Internal") { puts 'hi' }
      # OpenTelemetry API and New Relic API report the same trace ID
      assert_equal OpenTelemetry::Trace.current_span.context.trace_id, NewRelic::Agent::Tracer.current_transaction.guid

      # OpenTelemetry API and New Relic API report the same span ID
      assert_equal OpenTelemetry::Trace.current_span.context.span_id, NewRelic::Agent::Tracer.current_segment.guid
    end

    transactions = harvest_transaction_events![1]
    spans = harvest_span_events![1]

    assert_equal transactions[0][0]["name"], "Foo"
    assert_equal spans[0][0]["name"], "Bar"
    assert_equal spans[0][0]["category"], "generic"
    assert_equal spans[0][0]["parent_name"], "Foo"
    assert_equal spans[0][1]["name"], "Foo"
    assert_equal spans[0][1]["category"], "generic"
    assert spans[0][1]["nr.entryPoint"]
  end


end
