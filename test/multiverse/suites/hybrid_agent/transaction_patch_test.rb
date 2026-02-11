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

        # We want to verify the context switching works for both OTel and NR
        # Since the context switching methods are somewhat hidden within
        # the starting and finishing operations, we use the NR APIs to
        # start transactions and the OTel APIs to inject spans
        # rather than calling set_current_segment directly

        def test_adds_otel_span_to_segment
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            first_segment = txn.segments.first

            assert first_segment.instance_variable_defined?(:@otel_span), 'Segment should have an @otel_span'
          end
        end

        def test_transaction_start_sets_initial_context
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = txn.segments.first

            assert_equal segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should match segment's GUID"
            assert_equal segment.guid, NewRelic::Agent::Tracer.current_segment.guid, "Segment GUID should match first segment's GUID"
          end
        end

        def test_initial_nr_segment_linked_correctly_to_otel_span
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = txn.segments.first
            otel_span = segment.instance_variable_get(:@otel_span)

            assert_equal otel_span.context.span_id, segment.guid, "OTel span's ID should match segment's GUID"
            assert_nil otel_span.finishable, 'OTel span for NR-created initial segment should not have an OTel finishable'
          end
        end

        def test_start_nr_segment_updates_context
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            first_segment = txn.segments.first

            child_segment = Tracer.start_segment(name: 'child')
            child_otel_span = child_segment.instance_variable_get(:@otel_span)

            refute_equal first_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, 'OTel current span ID should have changed from first segment'
            assert_equal child_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should match child segment's GUID"
            assert_equal child_segment.guid, Tracer.current_segment.guid, 'NR current segment should be the child segment'
            assert_equal child_otel_span.context.span_id, child_segment.guid, "Child segment's @otel_span ID should match segment's GUID"

            child_segment.finish
          end
        end

        def test_finish_nr_segment_reverts_context_to_parent
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            first_segment = txn.segments.first

            child_segment = Tracer.start_segment(name: 'child')
            child_segment.finish

            assert_equal first_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should revert to first segment's GUID"
            assert_equal first_segment.guid, Tracer.current_segment.guid, "NR current segment GUID should revert to first segment's GUID"
            assert_predicate child_segment, :finished?, 'Child segment should be marked as finished'
          end
        end

        def test_otel_api_starts_span_within_nr_transaction
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            # Use the OTel API to start a span
            child_otel_span = ::OpenTelemetry.tracer_provider.tracer.start_span('otel_api_span')
            # finishable should be set by the start_span API
            child_nr_segment = child_otel_span.finishable

            assert_instance_of Transaction::Segment, child_nr_segment, "OTel span's finishable should be an NR Segment"
            assert_equal txn, child_nr_segment.transaction, 'NR segment created for OTel span should belong to the active transaction'
            assert_equal child_otel_span, child_nr_segment.instance_variable_get(:@otel_span), "NR segment's @otel_span should be the one created by the OTel API call"

            # Verify context update
            assert_equal child_nr_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should match OTel API created span's GUID"
            assert_equal child_nr_segment.guid, Tracer.current_segment.guid, 'NR current segment GUID should match segment for OTel API span'

            child_otel_span.finish
          end
        end

        def test_otel_api_finish_span_finishes_linked_nr_segment
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            child_otel_span = ::OpenTelemetry.tracer_provider.tracer.start_span('otel_api_span_to_finish')
            child_nr_segment = child_otel_span.finishable # This is the linked NR Segment

            child_otel_span.finish # Finish using OTel API

            assert_predicate child_nr_segment, :finished?, 'Linked NR segment should be marked as finished when OTel span is finished'
          end
        end

        def test_otel_api_cannot_finish_nr_api_created_elements
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = txn.segments.first
            otel_span = segment.instance_variable_get(:@otel_span)

            # Attempt to finish the OTel representation of the NR-created root segment
            otel_span.finish

            # The transaction itself should not be finished by this action
            refute_predicate txn, :finished?, "NR transaction should not be finished by OTel API call on its root segment's OTel span"
            refute_predicate segment, :finished?, 'NR root segment should not be finished by OTel API call on its OTel span'
          end
        end

        def test_nr_api_finishes_nr_transaction
          txn = Tracer.start_transaction(name: 'test', category: :web)
          txn.stubs(:sampled?).returns(true)
          txn.finish

          assert_predicate txn, :finished?, 'NR transaction should be marked as finished by NR API'
        end

        def test_finish_transaction_resets_contexts
          txn = Tracer.start_transaction(name: 'test', category: :web)
          txn.stubs(:sampled?).returns(true)
          txn.finish

          assert_equal ::OpenTelemetry::Trace::Span::INVALID, ::OpenTelemetry::Trace.current_span, 'OTel current span should be INVALID after transaction finish'
          assert_nil Tracer.current_transaction, 'NR current transaction should be nil after transaction finish'
          assert_nil Tracer.current_segment, 'NR current segment should be nil after transaction finish'
        end

        def test_current_span_delegates_when_context_provided
          context = ::OpenTelemetry::Context.empty
          original_result = ::OpenTelemetry::Trace.original_current_span(context)
          api_result = ::OpenTelemetry::Trace.current_span(context)

          assert_equal original_result, api_result, 'Should delegate to original when context provided'
        end

        def test_current_span_returns_original_without_transaction
          # Ensure no transaction is active and no thread-local span
          Thread.current[:nr_otel_current_span] = nil

          original_span = ::OpenTelemetry::Trace.original_current_span
          current_span = ::OpenTelemetry::Trace.current_span

          assert_equal original_span, current_span, 'Should return original span when no NR span available'
        end

        def test_current_span_returns_nr_span_in_transaction
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)

            nr_span = Thread.current[:nr_otel_current_span]
            current_span = ::OpenTelemetry::Trace.current_span

            assert_equal nr_span, current_span, 'Should return NR span when in transaction'
            assert_instance_of NewRelic::Agent::OpenTelemetry::Trace::Span, current_span
          end
        end

        def test_recursion_guard_prevents_infinite_loops
          thread = Thread.current

          # Test 1: Guard blocks recursive calls
          thread[:nr_otel_recursion_guard] = true
          thread[:nr_otel_current_span] = nil

          original_span = ::OpenTelemetry::Trace.original_current_span
          result = ::OpenTelemetry::Trace.current_span

          assert_equal original_span, result, 'Should return original span when guard is set'

          # Test 2: Guard is cleared properly in fallback path
          thread[:nr_otel_recursion_guard] = nil
          thread[:nr_otel_current_span] = nil

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

          # Thread 1 should get original span (guard active)
          # Thread 2 should get NR span (no guard, in transaction)
          original_span = ::OpenTelemetry::Trace.original_current_span

          assert_equal original_span, results[:thread1]
          assert_instance_of NewRelic::Agent::OpenTelemetry::Trace::Span, results[:thread2]
        end

        def test_thread_local_span_cleared_on_transaction_finish
          thread = Thread.current
          txn = Tracer.start_transaction(name: 'test_finish', category: :web)
          txn.stubs(:sampled?).returns(true)

          # Should have span set
          assert_instance_of NewRelic::Agent::OpenTelemetry::Trace::Span, thread[:nr_otel_current_span], 'Should have thread-local span set during transaction'

          txn.finish

          # Should be cleared after finish
          assert_nil thread[:nr_otel_current_span], 'Should clear thread-local span after transaction finish'
        end

        def test_thread_local_span_cleared_on_segment_removal
          thread = Thread.current

          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)

            child_segment = Tracer.start_segment(name: 'child')

            refute_nil thread[:nr_otel_current_span], 'Should have thread-local span during segment'

            txn.remove_current_segment_by_thread_id(thread.object_id)
            assert_nil thread[:nr_otel_current_span], 'Should clear thread-local span when segment removed'
            
            child_segment.finish
          end
        end

        def test_span_memoization_on_segment
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = txn.segments.first

            # First call should create span
            span1 = txn.send(:find_or_create_span, segment)

            # Second call should return memoized span
            span2 = txn.send(:find_or_create_span, segment)

            assert_same span1, span2, 'Should return same span instance (memoized)'
            assert segment.instance_variable_defined?(:@otel_span), 'Should memoize span on segment'
          end
        end

        def test_span_creation_handles_errors_gracefully
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)

            # Mock SpanContext.new to raise error
            ::OpenTelemetry::Trace::SpanContext.stubs(:new).raises(StandardError.new('SpanContext failed'))

            segment = Tracer.start_segment(name: 'error_test')

            # Should handle error gracefully
            span = txn.send(:find_or_create_span, segment)
            assert_nil span, 'Should return nil when span creation fails'

            # Should not crash transaction
            refute_predicate txn, :finished?, 'Transaction should continue after span creation error'

            segment.finish
            ::OpenTelemetry::Trace::SpanContext.unstub(:new)
          end
        end

        def test_thread_local_span_isolation_across_threads
          results = {}
          threads = []

          2.times do |i|
            threads << Thread.new do
              in_transaction(name: "txn_#{i}") do |txn|
                txn.stubs(:sampled?).returns(true)

                # Each thread should have its own NR span
                current_span = ::OpenTelemetry::Trace.current_span
                results[i] = {
                  span_id: current_span.context.span_id,
                  thread_local_span: Thread.current[:nr_otel_current_span]
                }
              end
            end
          end

          threads.each(&:join)

          # Each thread should have different span IDs
          refute_equal results[0][:span_id], results[1][:span_id], 'Threads should have different span IDs'

          # Thread-local spans should match API spans
          assert_equal results[0][:span_id], results[0][:thread_local_span].context.span_id, 'Thread 0 spans should match'
          assert_equal results[1][:span_id], results[1][:thread_local_span].context.span_id, 'Thread 1 spans should match'
        end

        def test_span_context_created_correctly_from_segment
          in_transaction do |txn|
            txn.stubs(:sampled?).returns(true)
            segment = Tracer.start_segment(name: 'context_test')

            span = txn.send(:find_or_create_span, segment)

            assert_instance_of NewRelic::Agent::OpenTelemetry::Trace::Span, span
            assert_equal segment.guid, span.context.span_id, 'Span ID should match segment GUID'
            assert_equal segment.transaction.trace_id, span.context.trace_id, 'Trace ID should match transaction trace ID'
            refute span.context.remote?, 'Span should not be remote'

            segment.finish
          end
        end
      end
    end
  end
end
