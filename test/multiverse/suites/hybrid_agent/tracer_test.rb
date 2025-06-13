# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class TracerTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new
          end

          def teardown
            NewRelic::Agent.instance.transaction_event_aggregator.reset!
            NewRelic::Agent.instance.span_event_aggregator.reset!
          end

          def test_in_span_creates_segment_when_span_kind_internal
            txn = in_transaction do
              @tracer.in_span('fruit', kind: :internal) { 'seeds' }
            end

            assert_includes(txn.segments.map(&:name), 'fruit')
          end

          def test_in_span_captures_error_when_span_kind_internal
            txn = nil
            begin
              in_transaction do |zombie_txn|
                txn = zombie_txn
                @tracer.in_span('brains', kind: :internal) { raise 'the dead' }
              end
            rescue => e
              # NOOP - allow transaction to capture error
            end

            assert_segment_noticed_error txn, /brains/, 'RuntimeError', /the dead/
            assert_transaction_noticed_error txn, 'RuntimeError'
          end

          def test_start_span_assigns_finishable_to_transaction
            otel_span = @tracer.start_span('otel_api_span')
            otel_finishable = otel_span.finishable

            assert_instance_of NewRelic::Agent::Transaction, otel_finishable, "OTel span's finishable should be an NR Transaction"

            otel_span.finish

            assert_predicate otel_finishable, :finished?, 'OTel span should finish NR transaction'
          end

          def test_parse_trace_flags_with_string
            assert_equal '42', @tracer.send(:parse_trace_flags, '42')
          end

          def test_parse_trace_flags_with_integer
            assert_equal '1', @tracer.send(:parse_trace_flags, 1)
          end

          def test_parse_trace_flags_with_sampled_otel_trace_flags
            flags = ::OpenTelemetry::Trace::TraceFlags::SAMPLED

            assert_equal '01', @tracer.send(:parse_trace_flags, flags)
          end

          def test_parse_trace_flags_with_unsampled_otel_trace_flags
            flags = ::OpenTelemetry::Trace::TraceFlags::DEFAULT

            assert_equal '00', @tracer.send(:parse_trace_flags, flags)
          end

          def test_set_nr_tracestate
            with_config(:account_id => '190', primary_application_id: '46954') do
              carrier = {
                'traceparent' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-00',
                'tracestate' => '190@nr=0-0-1-46954-7d3efb1b173fecfa-e8b91a159289ff74-00-00.23456-1518469636035'
              }
              propagator = NewRelic::Agent::OpenTelemetry::Context::Propagation::TracePropagator.new
              parent_context = propagator.extract(carrier)
              span = @tracer.start_span('test', with_parent: parent_context, kind: :server)

              distributed_tracer = span.finishable.distributed_tracer
              trace_state_payload = distributed_tracer.trace_state_payload

              assert_instance_of(NewRelic::Agent::TraceContextPayload, trace_state_payload)
              assert_equal('e8b91a159289ff74', trace_state_payload.transaction_id)
              refute_predicate span.finishable, :sampled?

              span.finish
            end
          end

          def test_set_otel_tracestate_with_newrelic_entry
            with_config(:account_id => '190', primary_application_id: '46954') do
              carrier = {
                'traceparent' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-00',
                'tracestate' => '190@nr=0-0-1-46954-7d3efb1b173fecfa-e8b91a159289ff74-00-00.23456-1518469636035'
              }

              prop = ::OpenTelemetry::Trace::Propagation::TraceContext::TextMapPropagator.new

              parent_context = prop.extract(carrier)
              span = @tracer.start_span('test', with_parent: parent_context, kind: :server)

              distributed_tracer = span.finishable.distributed_tracer
              trace_state_payload = distributed_tracer.trace_state_payload

              assert_instance_of(NewRelic::Agent::TraceContextPayload, trace_state_payload)
              assert_equal('e8b91a159289ff74', trace_state_payload.transaction_id)
              refute_predicate span.finishable, :sampled?

              span.finish
            end
          end

          def test_set_otel_tracestate_without_newrelic_entry
            with_config(:account_id => '190', primary_application_id: '46954') do
              carrier = {
                'traceparent' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-01',
                'tracestate' => ''
              }

              prop = ::OpenTelemetry::Trace::Propagation::TraceContext::TextMapPropagator.new

              parent_context = prop.extract(carrier)
              span = @tracer.start_span('test', with_parent: parent_context, kind: :server)

              distributed_tracer = span.finishable.distributed_tracer
              trace_state_payload = distributed_tracer.trace_state_payload

              assert_nil(trace_state_payload)
              # true because of the traceparent payload
              assert_predicate span.finishable, :sampled?

              span.finish
            end
          end

          def test_set_tracestate_with_nr_payload
            mock_distributed_tracer = Minitest::Mock.new
            mock_otel_context = Minitest::Mock.new
            nr_payload = NewRelic::Agent::TraceContextPayload.create(transaction_id: 'txn123')

            mock_otel_context.expect :tracestate, nr_payload

            @tracer.stub :set_nr_trace_state, ->(dt, oc) { :set_nr_trace_state_called } do
              result = @tracer.send(:set_tracestate, mock_distributed_tracer, mock_otel_context)

              assert_equal :set_nr_trace_state_called, result
            end

            mock_otel_context.verify
          end

          # def test_set_tracestate_with_otel_tracestate
          #   mock_distributed_tracer = Minitest::Mock.new
          #   mock_otel_context = Minitest::Mock.new
          #   otel_tracestate = ::OpenTelemetry::Trace::Tracestate.create('nr' => 'payload')

          #   mock_otel_context.expect :tracestate, otel_tracestate

          #   @tracer.stub :set_otel_trace_state, ->(dt, oc) { :set_otel_trace_state_called } do
          #     result = @tracer.send(:set_tracestate, mock_distributed_tracer, mock_otel_context)

          #     assert_equal :set_otel_trace_state_called, result
          #   end

          #   mock_otel_context.verify
          # end

          private

          def assert_logged(expected)
            found = NewRelic::Agent.logger.messages.any? { |m| m[1][0].match?(expected) }

            assert(found, "Didn't see log message: '#{expected}'. Saw: #{NewRelic::Agent.logger.messages}")
          end
        end
      end
    end
  end
end
