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
            mocha_teardown
            NewRelic::Agent.instance.transaction_event_aggregator.reset!
            NewRelic::Agent.instance.span_event_aggregator.reset!
          end

          def test_finish_does_not_fail_if_no_finishable_present
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new

            assert_nil span.finishable
            assert_nil span.finish
          end

          def test_finishable_can_finish_transactions
            span = @tracer.start_span('test', kind: :server)
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
              txn.stubs(:sampled?).returns(true)
              otel_span = @tracer.start_span('test_span')
              otel_span.add_attributes(attributes)
              otel_span.finish
            end

            spans = harvest_span_events![1]
            span_attributes = spans[0][1]

            assert_equal('california', span_attributes['yosemite'])
            assert_equal('wyoming', span_attributes['yellowstone'])
          end

          def test_recording_works_with_finishable_transactions_when_finished
            span = @tracer.start_span('test_span', kind: :server)

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
            span = @tracer.start_span('drip drop', kind: :server)

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
            span = @tracer.start_span(name, kind: :server)

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
              span = @tracer.start_span(name, kind: :server)

              span.finish

              span.name = updated_name
            end

            assert_log_contains(log, /WARN.*Calling name=/)
          end

          def test_status_works_with_description
            span = @tracer.start_span('oops', kind: :server)
            span.status = ::OpenTelemetry::Trace::Status.error('Something went wrong')
            txn = span.finishable

            txn.stubs(:sampled?).returns(true)
            span.finish

            # error is code 2
            expected = {'status.code' => 2, 'status.description' => 'Something went wrong'}

            segment_attrs = txn.segments.first.attributes
            segment_agent_attrs = segment_attrs.instance_variable_get(:@agent_attributes)

            assert_equal expected['status.code'], segment_agent_attrs['status.code']
            assert_equal expected['status.description'], segment_agent_attrs['status.description']

            # index 2 of the last_span_event array is for agent attributes
            last_span_agent_attrs = last_span_event[2]

            assert_equal expected['status.code'], last_span_agent_attrs['status.code']
            assert_equal expected['status.description'], last_span_agent_attrs['status.description']
          end

          def test_status_works_without_description
            span = @tracer.start_span('sleepy puppy', kind: :server)
            txn = span.finishable
            span.status = ::OpenTelemetry::Trace::Status.ok

            txn.stubs(:sampled?).returns(true)
            span.finish

            # ok is status code 0
            expected = {'status.code' => 0}

            segment_attrs = txn.segments.first.attributes
            segment_agent_attrs = segment_attrs.instance_variable_get(:@agent_attributes)

            assert_equal expected['status.code'], segment_agent_attrs['status.code']

            # index 2 of the last_span_event array is for agent attributes
            last_span_agent_attrs = last_span_event[2]

            assert_equal expected['status.code'], last_span_agent_attrs['status.code']
          end

          def test_default_status_is_unset
            span = @tracer.start_span('advil', kind: :server)
            txn = span.finishable

            assert_instance_of(::OpenTelemetry::Trace::Status, span.status)
            # unset is status code 1
            assert_equal(1, span.status.code)

            txn.stubs(:sampled?).returns(true)
            span.finish

            expected = {'status.code' => 1}

            segment_attrs = txn.segments.first.attributes
            segment_agent_attrs = segment_attrs.instance_variable_get(:@agent_attributes)

            assert_equal expected['status.code'], segment_agent_attrs['status.code']

            # index 2 of the last_span_event array is for agent attributes
            last_span_agent_attrs = last_span_event[2]

            assert_equal expected['status.code'], last_span_agent_attrs['status.code']
          end

          def test_transaction_returns_transaction_when_finishable_is_transaction
            span = @tracer.start_span('test', kind: :server)

            assert_instance_of NewRelic::Agent::Transaction, span.finishable
            assert_equal span.finishable, span.transaction

            span.finish
          end

          def test_transaction_returns_transaction_when_finishable_is_segment
            in_transaction do |txn|
              span = @tracer.start_span('test_segment')

              assert_instance_of NewRelic::Agent::Transaction::Segment, span.finishable
              assert_equal txn, span.transaction

              span.finish
            end
          end

          def test_transaction_memoizes_result
            span = @tracer.start_span('test', kind: :server)
            txn = span.finishable

            first_call = span.transaction
            second_call = span.transaction

            assert_equal txn, first_call
            assert_equal txn, second_call
            assert_same first_call, second_call

            span.finish
          end

          def test_transaction_returns_nil_when_finishable_is_nil
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new

            assert_nil span.finishable
            assert_nil span.transaction
          end

          def test_add_instrumentation_scope_adds_name_and_version_attributes
            scope_name = 'my-instrumentation-library'
            scope_version = '1.2.3'

            span = @tracer.start_span('test', kind: :server)
            txn = span.finishable
            txn.stubs(:sampled?).returns(true)

            span.add_instrumentation_scope(scope_name, scope_version)
            span.finish

            segment_attrs = txn.segments.first.attributes
            segment_agent_attrs = segment_attrs.instance_variable_get(:@agent_attributes)

            assert_equal scope_name, segment_agent_attrs['otel.scope.name']
            assert_equal scope_version, segment_agent_attrs['otel.scope.version']

            # index 2 of the last_span_event array is for agent attributes
            last_span_agent_attrs = last_span_event[2]

            assert_equal scope_name, last_span_agent_attrs['otel.scope.name']
            assert_equal scope_version, last_span_agent_attrs['otel.scope.version']
          end

          def test_add_instrumentation_scope_works_with_segment_finishable
            scope_name = 'segment-instrumentation'
            scope_version = '2.0.0'

            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)
              span = @tracer.start_span('test_segment')

              assert_instance_of NewRelic::Agent::Transaction::Segment, span.finishable

              span.add_instrumentation_scope(scope_name, scope_version)
              span.finish

              segment_attrs = txn.segments[1].attributes
              segment_agent_attrs = segment_attrs.instance_variable_get(:@agent_attributes)

              assert_equal scope_name, segment_agent_attrs['otel.scope.name']
              assert_equal scope_version, segment_agent_attrs['otel.scope.version']
            end
          end

          def test_add_instrumentation_scope_does_not_fail_with_nil_transaction
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new

            assert_nil span.transaction
            refute_raises { span.add_instrumentation_scope('test-scope', '1.0.0') }
          end

          def test_status_does_not_fail_with_nil_transaction
            span = NewRelic::Agent::OpenTelemetry::Trace::Span.new

            assert_nil span.transaction
            refute_raises { span.status = ::OpenTelemetry::Trace::Status.ok }
          end
        end
      end
    end
  end
end
