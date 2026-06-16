# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class SpanEventPrimitivePatchTest < Minitest::Test
        def test_span_kind_added_to_intrinsics_when_otel_span_has_kind
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = txn.current_segment
            otel_span = stub(kind: :server)
            segment.instance_variable_set(:@otel_span, otel_span)

            intrinsics, = SpanEventPrimitive.for_segment(segment)

            assert_equal 'server', intrinsics['span.kind']
          end
        end

        def test_span_kind_not_added_to_intrinsics_without_otel_span
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = txn.current_segment

            intrinsics, = SpanEventPrimitive.for_segment(segment)

            refute intrinsics.key?('span.kind')
          end
        end

        def test_span_kind_not_added_to_intrinsics_when_otel_span_kind_is_nil
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = txn.current_segment
            otel_span = stub(kind: nil)
            segment.instance_variable_set(:@otel_span, otel_span)

            intrinsics, = SpanEventPrimitive.for_segment(segment)

            refute intrinsics.key?('span.kind')
          end
        end
      end
    end
  end
end
