# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class SpanTest < Minitest::Test
          Segment = Struct.new(:guid, :transaction)
          Transaction = Struct.new(:trace_id)

          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new
          end

          def teardown
            NewRelic::Agent.instance.transaction_event_aggregator.reset!
            NewRelic::Agent.instance.span_event_aggregator.reset!
          end

          def test_finish_does_not_fail_if_no_finishable_present
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new

            assert_nil span.finishable
            assert_nil span.finish
          end

          def test_finishable_can_finish_transactions
            txn = NewRelic::Agent::Tracer.start_transaction_or_segment(category: :web, name: 'test')
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new
            span.finishable = txn
            span.finish

            assert_predicate span.finishable, :finished?
            assert_predicate txn, :finished?
          end

          def test_finishable_can_finish_segments
            segment = NewRelic::Agent::Transaction::Segment.new
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new
            span.finishable = segment
            span.finish

            assert_predicate span.finishable, :finished?
            assert_predicate segment, :finished?
          end

          def test_add_attributes_patch_for_spans
            attributes = {
              'yosemite' => 'california',
              'yellowstone' => 'wyoming'
            }
            in_transaction do |txn|
              NewRelic::Agent.instance.adaptive_sampler.stub(:sampled?, true) do
                otel_span = @tracer.start_span('test_span')
                otel_span.add_attributes(attributes)
                otel_span.finish
              end
            end
            spans = harvest_span_events![1]
            span_attributes = spans[0][1]

            assert_equal span_attributes, attributes
          end
        end
      end
    end
  end
end
