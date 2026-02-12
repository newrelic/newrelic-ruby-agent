# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class TransactionPatchTest < Minitest::Test
        def teardown
          NewRelic::Agent.instance.transaction_event_aggregator.reset!
          NewRelic::Agent.instance.span_event_aggregator.reset!
        end

        def test_recursion_guard_calls_original_current_span_when_set
          thread = Thread.current
          thread[:nr_otel_recursion_guard] = true
          thread[:nr_otel_current_span] = nil
          result = ::OpenTelemetry::Trace.current_span

          # The OTel default return value for spans without context is INVALID
          assert_equal ::OpenTelemetry::Trace::Span::INVALID, result, 'Should delegate to original when guard is set'

          # Cleanup to prevent leaking state into other tests
          thread[:nr_otel_recursion_guard] = nil
          thread[:nr_otel_current_span] = nil
        end

        def test_recursion_guard_is_cleared_after_fallback
          thread = Thread.current
          # With a nil nr_otel_recursion_guard, it should be reset to true during fallback and then cleared
          ::OpenTelemetry::Trace.current_span

          assert_nil thread[:nr_otel_recursion_guard], 'Guard should be cleared after fallback'
        end

        def test_recursion_guard_is_thread_local
          results = {}
          threads = []

          # Start first thread with recursion guard set
          threads << Thread.new do
            Thread.current[:nr_otel_recursion_guard] = true
            results[:thread1] = ::OpenTelemetry::Trace.current_span
          end

          # Start second thread without recursion guard
          threads << Thread.new do
            in_transaction do |txn|
              txn.stubs(:sampled?).returns(true)
              results[:thread2] = ::OpenTelemetry::Trace.current_span
            end
          end

          threads.each(&:join)

          assert_equal ::OpenTelemetry::Trace::Span::INVALID, results[:thread1], 'Thread with guard should get original span'
          assert_instance_of NewRelic::Agent::OpenTelemetry::Trace::Span, results[:thread2], 'Thread without guard should get NR span'
        end
      end
    end
  end
end
