# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class SpanTest < Minitest::Test
          # Tests in this file can easily become flaky and influence
          # other files. Best practice is to use @tracer.start_span
          # to create Spans and to finish all the spans you start.

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
            span = @tracer.start_span('test')
            txn = span.finishable
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

            assert_includes span_attributes.keys, 'yosemite'
            assert_includes span_attributes.keys, 'yellowstone'
          end

          def test_recording_works_with_finishable_transactions_when_finished
            span = @tracer.start_span('test_span')

            assert_instance_of NewRelic::Agent::Transaction, span.finishable

            span.finish

            refute_predicate span, :recording?
          end

          def test_recording_works_with_finishable_segments_when_finished
            in_transaction do
              span = @tracer.start_span('hehe')

              assert_instance_of NewRelic::Agent::Transaction::Segment, span.finishable

              span.finish

              refute_predicate span, :recording?
            end
          end

          def test_recording_works_with_finishable_transactions_when_not_finished
            span = @tracer.start_span('drip drop')

            assert_instance_of NewRelic::Agent::Transaction, span.finishable
            assert_predicate span, :recording?

            span.finish
          end

          def test_recording_works_with_finishable_segments_when_not_finished
            segment = NewRelic::Agent::Transaction::Segment.new
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new
            span.finishable = segment

            assert_predicate span, :recording?

            span.finish
          end

          def test_name_works_with_finishable_transaction
            name = 'initial_name'
            updated_name = 'updated_name'
            span = @tracer.start_span(name)

            assert_instance_of NewRelic::Agent::Transaction, span.finishable

            transaction = span.finishable
            span.name = updated_name

            assert_equal updated_name, transaction.best_name

            span.finish
          end

          def test_name_works_with_finishable_segment
            in_transaction do
              name = 'initial_name'
              updated_name = 'updated_name'

              span = @tracer.start_span(name)

              assert_instance_of NewRelic::Agent::Transaction::Segment, span.finishable

              span.name = updated_name
              segment = span.finishable

              assert_equal updated_name, segment.name

              span.finish
            end
          end

          def test_message_logged_when_name_called_but_span_is_finished
            log = with_array_logger do
              NewRelic::Agent.manual_start

              name = 'initial_name'
              updated_name = 'updated_name'
              span = @tracer.start_span(name)

              span.finish

              span.name = updated_name
            end

            assert_log_contains(log, /WARN.*Calling name=/)
          end

          def test_status_works_with_description
            span = @tracer.start_span('oops')
            span.status = ::OpenTelemetry::Trace::Status.error('Something went wrong')
            span.finish

            # error is code 2
            expected = {'status.code' => 2, 'status.description' => 'Something went wrong'}

            assert_equal expected, last_span_event[1]
          end

          def test_status_works_without_description
            span = @tracer.start_span('sleepy puppy')
            span.status = ::OpenTelemetry::Trace::Status.ok
            span.finish

            # ok is status code 0
            expected = {'status.code' => 0}

            assert_equal expected, last_span_event[1]
          end

          def test_default_status_is_unset
            span = @tracer.start_span('advil')

            assert_instance_of(::OpenTelemetry::Trace::Status, span.status)
            assert_equal(1, span.status.code)

            span.finish
          end
        end
      end
    end
  end
end
