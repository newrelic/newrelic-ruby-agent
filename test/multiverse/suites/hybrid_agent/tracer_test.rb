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
              NewRelic::Agent.instance.adaptive_sampler.stub(:sampled?, true) do
                @tracer.in_span('fruit', kind: :internal) { 'seeds' }
              end
            end

            assert_includes(txn.segments.map(&:name), 'fruit')
          end

          def test_in_span_captures_error_when_span_kind_internal
            txn = nil
            begin
              in_transaction do |zombie_txn|
                NewRelic::Agent.instance.adaptive_sampler.stub(:sampled?, true) do
                  txn = zombie_txn
                  @tracer.in_span('brains', kind: :internal) { raise 'the dead' }
                end
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

          def test_start_span_with_attributes_captures_attributes
            attributes = {'strawberry' => 'red'}
            txn = in_transaction do
              NewRelic::Agent.instance.adaptive_sampler.stub(:sampled?, true) do
                otel_span = @tracer.start_span('test_span', attributes: attributes)
                otel_span.finish
              end
            end
            spans = harvest_span_events![1]
            span_attributes = spans[0][1]

            assert_equal span_attributes, attributes
          end

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
