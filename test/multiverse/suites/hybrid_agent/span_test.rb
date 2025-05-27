# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class SpanTest < Minitest::Test
          include MultiverseHelpers
          setup_and_teardown_agent

          Segment = Struct.new(:guid, :transaction)
          Transaction = Struct.new(:trace_id)

          def after_setup
            puts @NAME
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
        end
      end
    end
  end
end
