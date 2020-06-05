# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic
  module Agent
    module SpanEventPrimitive
      class SpanEventPrimativeTest < Minitest::Test

        def setup
          @additional_config = { :'distributed_tracing.enabled' => true }
          NewRelic::Agent.config.add_config_for_testing(@additional_config)
          NewRelic::Agent.config.notify_server_source_added
          nr_freeze_time
        end

        def teardown
          NewRelic::Agent.config.remove_config(@additional_config)
          reset_buffers_and_caches
        end

        def test_error_attributes_returns_nil_when_no_error
          with_segment do |segment|
            eh = SpanEventPrimitive::error_attributes(segment)
            refute segment.noticed_error, "segment.noticed_error expected to be nil!"
            refute eh, "expected nil when no error present on segment"
          end
        end

        def test_error_attributes_returns_populated_attributes_when_error_present
            segment, _ = capture_segment_with_error

          eh = SpanEventPrimitive::error_attributes(segment)
          assert segment.noticed_error, "segment.noticed_error should NOT be nil!"
          assert eh.is_a?(Hash), "expected a Hash when error present on segment"
          assert_equal "oops!", eh["error.message"]
          assert_equal "RuntimeError", eh["error.class"]
        end

        def test_does_not_add_error_attributes_in_high_security
          with_config(:high_security => true) do
            segment, _ = capture_segment_with_error

            eh = SpanEventPrimitive::error_attributes(segment)
            refute  segment.noticed_error, "segment.noticed_error should be nil!"
            refute eh, "expected nil when error present on segment and high_security is enabled"
          end
        end

        def test_does_not_add_error_message_when_strip_message_enabled
          with_config(:'strip_exception_messages.enabled' => true) do
            segment, _ = capture_segment_with_error

            eh = SpanEventPrimitive::error_attributes(segment)
            assert segment.noticed_error, "segment.noticed_error should NOT be nil!"
            assert eh.is_a?(Hash), "expected a Hash when error present on segment"
            assert eh["error.message"].start_with?("Message removed by")
            assert_equal "RuntimeError", eh["error.class"]
          end
        end

        def test_root_span_gets_transaction_name_attribute
          root_span_event = nil
          root_segment = nil

          txn = in_transaction do |txn|
            root_segment = txn.current_segment
          end

          root_span_event = SpanEventPrimitive.for_segment(root_segment)

          # There should be a transaction.name attribute on the root span equal to the final txn name
          assert_equal txn.best_name, root_span_event[0]["transaction.name"]
        end

        def test_empty_error_message_can_override_previous_error_message_attribute
          begin
            with_segment do |segment|
              segment.notice_error RuntimeError.new "oops!"
              segment.notice_error StandardError.new
              error_attributes = SpanEventPrimitive::error_attributes(segment)
              assert segment.noticed_error, "segment.noticed_error should NOT be nil!"
              assert_equal "StandardError", error_attributes["error.class"]
              # If no message given, we should see the class name as the new error message
              assert_equal "StandardError", error_attributes["error.message"]
            end
          end
        end

        def test_transaction_level_custom_attributes_added_to_span_events
          with_config(:'span_events.attributes.enabled' => true) do
            with_segment do |segment|
              NewRelic::Agent.add_custom_attributes(:foo => "bar")
              txn = NewRelic::Agent::Tracer.current_transaction
              span_event = SpanEventPrimitive.for_segment(segment)

              transaction_custom_attributes = txn.attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
              span_custom_attributes = span_event[1]

              assert_equal({"foo" => "bar"}, span_custom_attributes)
              assert_equal transaction_custom_attributes, span_custom_attributes
            end
          end
        end

        def test_span_level_custom_attributes_always_override_transaction_level_custom_attributes
          with_config(:'span_events.attributes.enabled' => true) do
            # Attributes added via add_custom_span_attributes should override those added via add_custom_attributes
            with_segment do |segment|
              NewRelic::Agent.add_custom_attributes(:foo => "bar")
              NewRelic::Agent.add_custom_span_attributes(:foo => "baz")

              txn = NewRelic::Agent::Tracer.current_transaction
              span_event = SpanEventPrimitive.for_segment(segment)

              transaction_custom_attributes = txn.attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
              span_custom_attributes = span_event[1]

              assert_equal({"foo" => "baz"}, span_custom_attributes)
              refute_equal transaction_custom_attributes, span_custom_attributes
            end

            # Span attributes should still be preferred even if add_custom_span_attributes is called before add_custom_attributes
            with_segment do |segment|
              NewRelic::Agent.add_custom_span_attributes(:foo => "baz")
              NewRelic::Agent.add_custom_attributes(:foo => "bar")

              txn = NewRelic::Agent::Tracer.current_transaction
              span_event = SpanEventPrimitive.for_segment(segment)

              transaction_custom_attributes = txn.attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
              span_custom_attributes = span_event[1]

              assert_equal({"foo" => "baz"}, span_custom_attributes)
              refute_equal transaction_custom_attributes, span_custom_attributes
            end
          end
        end
      end
    end
  end
end
