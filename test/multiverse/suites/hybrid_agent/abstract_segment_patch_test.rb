# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class AbstractSegmentPatchTest < Minitest::Test
        def setup
          harvest_transaction_events!
          harvest_span_events!
        end

        def test_force_finish_with_otel_span_that_cannot_finish_segment
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = Tracer.start_segment(name: 'test_segment')
            otel_span = segment.instance_variable_get(:@otel_span)

            otel_span.stubs(:instance_variable_get).with(:@finished).returns(false)
            otel_span.stubs(:finish).returns(nil)

            segment.force_finish

            assert_predicate segment, :finished?
          end
        end

        def test_force_finish_with_successful_otel_span_finish
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = Tracer.start_segment(name: 'test_segment')
            otel_span = segment.instance_variable_get(:@otel_span)

            otel_span.stubs(:instance_variable_get).with(:@finished).returns(false)
            otel_span.stubs(:finish) do
              segment.finish
            end

            refute_predicate segment, :finished?, 'Segment should start unfinished'

            segment.force_finish

            assert_predicate segment, :finished?, 'Segment should be finished by span.finish'
          end
        end

        def test_force_finish_handles_otel_span_exceptions_gracefully
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = Tracer.start_segment(name: 'test_segment')
            otel_span = segment.instance_variable_get(:@otel_span)

            otel_span.stubs(:instance_variable_get).with(:@finished).returns(false)
            otel_span.stubs(:finish).raises(StandardError.new('Test exception'))

            logger_mock = mock()
            logger_mock.expects(:debug).with(regexp_matches(/Error finishing OpenTelemetry span during force_finish.*Test exception/))
            NewRelic::Agent.stubs(:logger).returns(logger_mock)

            segment.force_finish

            assert_predicate segment, :finished?, 'Segment should still be finished via fallback after exception'
          end
        end
      end
    end
  end
end
