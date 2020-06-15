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

        def test_root_span_gets_dt_parent_attributes
          NewRelic::Agent.instance.span_event_aggregator.stubs(:enabled?).returns(true)
          NewRelic::Agent::Transaction.any_instance.stubs(:sampled?).returns(true)
          NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)

          @config = {
            :'distributed_tracing.enabled' => true,
            :account_id => "190",
            :primary_application_id => "46954",
            :trusted_account_key => "trust_this!"
          }

          NewRelic::Agent.config.add_config_for_testing(@config)

          payload = nil
          external_segment = nil
          in_transaction('test_txn') do |txn|
            external_segment = NewRelic::Agent::Tracer.\
                         start_external_request_segment library: "net/http",
                                                        uri: "http://docs.newrelic.com",
                                                        procedure: "GET"
            payload = txn.distributed_tracer.create_distributed_trace_payload
          end

          in_transaction('test_txn2') do |txn|
            incoming_payload = payload.text
            txn.distributed_tracer.accept_distributed_trace_payload incoming_payload
          end

          last_span_event = NewRelic::Agent.agent.span_event_aggregator.harvest![-1][-1]

          assert last_span_event[2]["parent.type"], "Expected parent.type in agent attributes"
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

        def test_includes_custom_attributes_in_event
          in_transaction do |txn|
            txn.current_segment.attributes.merge_custom_attributes('bing' => 2)
            _, custom_attrs, _ = SpanEventPrimitive.for_segment txn.current_segment
            assert_equal 2, custom_attrs['bing']
          end
        end

        def test_doesnt_include_custom_attributes_in_event_when_configured_not_to
          with_config('span_events.attributes.enabled' => false) do
            with_segment do |segment|
              segment.attributes.merge_custom_attributes('bing' => 2)
              _, custom_attrs, _ = SpanEventPrimitive.for_segment segment
              assert_empty custom_attrs
            end
          end
        end

        def test_custom_attributes_in_event_cant_override_reserved_attributes
          with_segment do |segment|
            segment.attributes.merge_custom_attributes('type' => 'giraffe', 'duration' => 'hippo')
            event, custom_attrs, _ = SpanEventPrimitive.for_segment segment

            assert_equal 'Span', event['type']
            assert_equal 0.0, event['duration']

            assert_equal 'giraffe', custom_attrs['type']
            assert_equal 'hippo', custom_attrs['duration']
          end
        end

        def test_custom_span_attributes_not_added_to_transaction_events
          with_segment do |segment, txn|
            expected_span_attrs = {'foo' => 'bar'}
            segment.attributes.merge_custom_attributes(expected_span_attrs)

            filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
            attributes = NewRelic::Agent::Attributes.new(filter)

            payload = {
              :name => "Controller/whatever",
              :type => :controller,
              :start_timestamp =>  Time.now.to_f,
              :duration => 0.1,
              :attributes => attributes,
              :error => false,
              :priority => 0.123
            }
            _, custom_txn_attrs, _ = TransactionEventPrimitive.create payload

            _, custom_span_attrs, _ = SpanEventPrimitive.for_segment segment

            assert_empty custom_txn_attrs
            assert_equal expected_span_attrs, custom_span_attrs
          end
        end

        def test_attribute_exclusion
          external_segment = nil
          with_config(:'attributes.exclude' => ['http.url']) do
            in_transaction('test_txn') do |t|
              t.stubs(:sampled?).returns(true)
              external_segment = Tracer.start_external_request_segment(library: 'Net::HTTP',
                                                                            uri: "https://docs.newrelic.com",
                                                                            procedure: "GET")
              external_segment.finish
            end
          end

          last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          _, optional_attrs, _ = last_span_events.detect { |ev| ev[0]["name"] == external_segment.name }

          assert_empty optional_attrs
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

        def test_transaction_level_agent_attributes_added_to_span_events
          span_event = nil

          with_config(:'span_events.attributes.enabled' => true) do
            _segment, transaction = with_segment do |segment|
              txn = NewRelic::Agent::Tracer.current_transaction
              txn.add_agent_attribute(:foo, "bar", AttributeFilter::DST_ALL)
              span_event = SpanEventPrimitive.for_segment(segment)
            end

            transaction_agent_attributes = transaction.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
            span_agent_attributes = span_event[2]

            assert_equal({:foo => "bar"}, span_agent_attributes)
            assert_equal transaction_agent_attributes, span_agent_attributes
          end
        end
      end
    end
  end
end
