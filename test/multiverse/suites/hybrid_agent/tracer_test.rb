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

          def test_in_span_logs_when_span_kind_unknown
            NewRelic::Agent.stub(:logger, NewRelic::Agent::MemoryLogger.new) do
              @tracer.in_span('fruit', kind: :mango) { 'yep' }

              assert_logged(/Span kind: mango is not supported yet/)
            end
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
