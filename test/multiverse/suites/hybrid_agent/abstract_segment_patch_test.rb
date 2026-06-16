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

          def test_span_events_returns_empty_array_when_no_events
            with_segment do |segment|
              assert_equal NewRelic::EMPTY_ARRAY, segment.span_events
            end
          end

          def test_add_span_event_stores_event
            with_segment do |segment|
              segment.add_span_event('my_event', attributes: {'key' => 'val'})

              assert_equal 1, segment.span_events.length
              assert_equal 'my_event', segment.span_events.first[:name]
              assert_equal({'key' => 'val'}, segment.span_events.first[:attributes])
            end
          end

          def test_add_span_event_stores_provided_timestamp
            t = Time.now

            with_segment do |segment|
              segment.add_span_event('ts_event', timestamp: t)

              assert_equal t, segment.span_events.first[:timestamp]
            end
          end

          def test_add_span_event_uses_current_time_when_no_timestamp_provided
            with_segment do |segment|
              segment.add_span_event('no_ts_event')

              assert_kind_of Numeric, segment.span_events.first[:timestamp]
            end
          end

          def test_add_span_event_normalizes_integer_nanosecond_timestamp
            # See: https://github.com/open-telemetry/opentelemetry-ruby/blob/main/sdk/lib/opentelemetry/sdk/trace/span.rb#L462-L475
            # for time conversion methods used in the OTel SDK on Spans
            ns = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
            ns_integer = (ns.to_r * 1_000_000_000).to_i

            with_segment do |segment|
              segment.add_span_event('ns_event', timestamp: ns_integer)
              stored = segment.span_events.first[:timestamp]

              assert_in_delta ns_integer / 1_000_000_000.0, stored, 0.001
            end
          end

          def test_add_span_event_enforces_max_limit_and_records_dropped_metric
            with_segment do |segment|
              102.times { |i| segment.add_span_event("event_#{i}") }

              assert_equal 100, segment.span_events.length
            end

            assert_metrics_recorded({'Supportability/Ruby/SpanEvent/Events/Dropped' => {call_count: 2}})
          end
        end
      end
    end
  end
end
