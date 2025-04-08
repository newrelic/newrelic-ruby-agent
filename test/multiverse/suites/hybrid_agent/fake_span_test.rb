# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class FakeSpanTest < Minitest::Test
          Segment = Struct.new(:guid)
          Transaction = Struct.new(:trace_id)

          def test_fake_span_has_context
            segment = Segment.new('123')
            transaction = Transaction.new('456')

            span = FakeSpan.new(segment: segment, transaction: transaction)

            assert_equal '123', span.context.span_id
            assert_equal '456', span.context.trace_id
            assert_equal 1, span.context.trace_flags
          end
        end
      end
    end
  end
end
