# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class TransactionStartingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new
            # just to be extra safe to make sure finishable is the correct class
            NewRelic::Agent::Tracer.current_transaction&.finish
          end

          def teardown
            NewRelic::Agent.instance.transaction_event_aggregator.reset!
            NewRelic::Agent.instance.span_event_aggregator.reset!
          end

          def test_span_with_remote_parent_makes_web_transaction_when_kind_client
            otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :client)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :web, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_with_remote_parent_makes_web_transaction_when_kind_server
            otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :server)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :web, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_with_remote_parent_makes_other_transaction_when_kind_consumer
            otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :consumer)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :task, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_with_remote_parent_makes_other_transaction_when_kind_producer
            otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :producer)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :task, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_with_remote_parent_makes_other_transaction_when_kind_internal
            otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :internal)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :task, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_with_remote_parent_makes_other_transaction_when_kind_unspecified
            skip 'have yet to implement'
            otel_span = @tracer.start_span('name', with_parent: remote_context)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :task, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_without_remote_parent_starts_new_web_transaction_when_kind_server
            otel_span = @tracer.start_span('name', with_parent: ::OpenTelemetry::Context::ROOT, kind: :server)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :web, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_without_remote_parent_starts_new_other_transaction_when_kind_consumer
            otel_span = @tracer.start_span('name', with_parent: ::OpenTelemetry::Context::ROOT, kind: :consumer)

            assert_instance_of NewRelic::Agent::Transaction, otel_span.finishable
            assert_equal :task, otel_span.finishable.category

            otel_span.finish
          end

          def test_span_without_remote_parent_does_not_start_transaction_when_kind_client
            otel_span = @tracer.start_span('name', with_parent: ::OpenTelemetry::Context::ROOT, kind: :client)

            assert_nil otel_span
          end

          def test_span_without_remote_parent_does_not_start_transaction_when_kind_internal
            otel_span = @tracer.start_span('name', with_parent: ::OpenTelemetry::Context::ROOT, kind: :internal)

            assert_nil otel_span
          end

          def test_span_without_remote_parent_does_not_start_transaction_when_kind_producer
            otel_span = @tracer.start_span('name', with_parent: ::OpenTelemetry::Context::ROOT, kind: :producer)

            assert_nil otel_span
          end

          def test_span_without_remote_parent_does_not_start_transaction_when_kind_unspecified
            otel_span = @tracer.start_span('name', with_parent: ::OpenTelemetry::Context::ROOT)

            assert_nil otel_span
          end

          def test_span_with_remote_parent_and_current_transaction_creates_segment_when_kind_server
            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)

              otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :server)

              assert_instance_of NewRelic::Agent::Transaction::Segment, otel_span.finishable
              assert_equal txn, otel_span.finishable.transaction

              otel_span.finish
            end
          end

          def test_span_with_remote_parent_and_current_transaction_creates_segment_when_kind_consumer
            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)

              otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :consumer)

              assert_instance_of NewRelic::Agent::Transaction::Segment, otel_span.finishable
              assert_equal txn, otel_span.finishable.transaction

              otel_span.finish
            end
          end

          def test_span_with_remote_parent_and_current_transaction_creates_segment_when_kind_client
            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)

              otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :client)

              assert_instance_of NewRelic::Agent::Transaction::Segment, otel_span.finishable
              assert_equal txn, otel_span.finishable.transaction

              otel_span.finish
            end
          end

          def test_span_with_remote_parent_and_current_transaction_creates_segment_when_kind_producer
            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)

              otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :producer)

              assert_instance_of NewRelic::Agent::Transaction::Segment, otel_span.finishable
              assert_equal txn, otel_span.finishable.transaction

              otel_span.finish
            end
          end

          def test_span_with_remote_parent_and_current_transaction_creates_segment_when_kind_internal
            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)

              otel_span = @tracer.start_span('name', with_parent: remote_context, kind: :internal)

              assert_instance_of NewRelic::Agent::Transaction::Segment, otel_span.finishable
              assert_equal txn, otel_span.finishable.transaction

              otel_span.finish
            end
          end

          def test_span_with_remote_parent_and_current_transaction_creates_segment_when_kind_unspecified
            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)

              otel_span = @tracer.start_span('name', with_parent: remote_context)

              assert_instance_of NewRelic::Agent::Transaction::Segment, otel_span.finishable
              assert_equal txn, otel_span.finishable.transaction

              otel_span.finish
            end
          end

          private

          def remote_context
            carrier = {
              'traceparent' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-01',
              'tracestate' => ''
            }

            prop = ::OpenTelemetry::Trace::Propagation::TraceContext::TextMapPropagator.new

            prop.extract(carrier)
          end
        end
      end
    end
  end
end
