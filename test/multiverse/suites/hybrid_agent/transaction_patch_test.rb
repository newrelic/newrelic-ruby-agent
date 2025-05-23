# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class TransactionPatchTest < Minitest::Test
        include MultiverseHelpers
        setup_and_teardown_agent
        # We want to verify that the context switching works for both OTel
        # and NR
        # Since the context switching methods are somewhat hidden within
        # the starting and finishing operations, we use the NR APIs to
        # start transactions and the OTel APIs to inject spans
        # rather than calling set_current_segment directly
        def after_setup
          puts @NAME
          @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new
        end

        def test_adds_otel_span_to_segment
          txn = NewRelic::Agent::Tracer.start_transaction_or_segment(name: 'test', category: :otel)
          first_segment = txn.segments.first

          assert first_segment.instance_variable_defined?(:@otel_span), 'NR first segment should have an @otel_span'

          txn.finish
        end

        def test_transaction_start_sets_initial_context
          txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)
          first_segment = txn.segments.first

          assert_equal first_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should match first segment's GUID"
          assert_equal first_segment.guid, NewRelic::Agent::Tracer.current_segment.guid, "NR current segment GUID should match first segment's GUID"

          txn.finish
        end

        def test_initial_nr_segment_linked_correctly_to_otel_span
          txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)
          first_segment = txn.segments.first
          first_otel_span = first_segment.instance_variable_get(:@otel_span)

          assert_equal first_otel_span.context.span_id, first_segment.guid, "OTel span's ID should match first segment's GUID"
          assert_nil first_otel_span.finishable, 'OTel span for NR-created initial segment should not have an OTel finishable'

          txn.finish
        end

        def test_start_nr_segment_updates_context
          txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)
          first_segment = txn.segments.first

          child_segment = NewRelic::Agent::Tracer.start_segment(name: 'child')
          child_otel_span = child_segment.instance_variable_get(:@otel_span)

          refute_equal first_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should have changed from first segment"
          assert_equal child_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should match child segment's GUID"
          assert_equal child_segment.guid, NewRelic::Agent::Tracer.current_segment.guid, "NR current segment should be the child segment"
          assert_equal child_otel_span.context.span_id, child_segment.guid, "Child segment's @otel_span ID should match segment's GUID"

          child_segment.finish
          txn.finish
        end

        def test_finish_nr_segment_reverts_context_to_parent
          txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)
          first_segment = txn.segments.first

          child_segment = NewRelic::Agent::Tracer.start_segment(name: 'child')
          child_segment.finish

          assert_equal first_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should revert to first segment's GUID"
          assert_equal first_segment.guid, NewRelic::Agent::Tracer.current_segment.guid, "NR current segment GUID should revert to first segment's GUID"
          assert_predicate child_segment, :finished?, 'Child segment should be marked as finished'

          txn.finish
        end

        # def test_otel_api_starts_span_within_nr_transaction
        #   txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)

        #   # Use the OTel API to start a span
        #   child_otel_span = @tracer.start_span('otel_api_span')
        #   # finishable should be set by the start_span API
        #   child_nr_segment = child_otel_span.finishable

        #   assert_instance_of NewRelic::Agent::Transaction::Segment, child_nr_segment, "OTel span's finishable should be an NR Segment"
        #   assert_equal txn, child_nr_segment.transaction, "NR segment created for OTel span should belong to the active transaction"
        #   assert_equal child_otel_span, child_nr_segment.instance_variable_get(:@otel_span), "NR segment's @otel_span should be the one created"

        #   # Verify context update
        #   assert_equal child_nr_segment.guid, ::OpenTelemetry::Trace.current_span.context.span_id, "OTel current span ID should match OTel API created span's GUID"
        #   assert_equal child_nr_segment.guid, NewRelic::Agent::Tracer.current_segment.guid, "NR current segment GUID should match segment for OTel API span"

        #   child_otel_span.finish
        #   txn.finish
        # end

        # def test_otel_api_finish_span_finishes_linked_nr_segment
        #   txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)

        #   child_otel_span = @tracer.start_span('otel_api_span_to_finish')
        #   child_nr_segment = child_otel_span.finishable # This is the linked NR Segment

        #   child_otel_span.finish # Finish using OTel API

        #   assert_predicate child_nr_segment, :finished?, "Linked NR segment should be marked as finished when OTel span is finished"

        #   txn.finish
        # end

        # def test_otel_api_cannot_finish_nr_api_created_elements
        #   txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)
        #   first_segment = txn.segments.first
        #   first_otel_span = first_segment.instance_variable_get(:@otel_span)

        #   # Attempt to finish the OTel representation of the NR-created root segment
        #   first_otel_span.finish

        #   # The transaction itself should not be finished by this action
        #   refute_predicate txn, :finished?, "NR transaction should not be finished by OTel API call on its root segment's OTel span"
        #   refute_predicate first_segment, :finished?, "NR root segment should not be finished by OTel API call on its OTel span"

        #   txn.finish
        # end

        #   def test_nr_api_finishes_nr_transaction
        #     txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)
        #     txn.finish

        #     assert_predicate txn, :finished?, "NR transaction should be marked as finished by NR API"
        #   end

        def test_finish_transaction_resets_contexts
          txn = NewRelic::Agent::Tracer.start_transaction(name: 'test', category: :otel)
          txn.finish

          assert_equal ::OpenTelemetry::Trace::Span::INVALID, ::OpenTelemetry::Trace.current_span, 'OTel current span should be INVALID after transaction finish'
          assert_nil NewRelic::Agent::Tracer.current_transaction, 'NR current transaction should be nil after transaction finish'
          assert_nil NewRelic::Agent::Tracer.current_segment, 'NR current segment should be nil after transaction finish'
        end
      end
    end
  end
end
