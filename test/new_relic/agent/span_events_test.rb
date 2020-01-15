# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/transaction_event_primitive'

module NewRelic
  module Agent
    class SpanEventsTest < Minitest::Test
      def setup
        @config = {
          :'distributed_tracing.enabled' => true,
          :account_id => "190",
          :primary_application_id => "46954",
          :trusted_account_key => "trust_this!"
        }

        NewRelic::Agent.config.add_config_for_testing(@config)
        NewRelic::Agent.config.notify_server_source_added
      end

      def teardown
        NewRelic::Agent.config.remove_config(@config)
        NewRelic::Agent.config.reset_to_defaults
        NewRelic::Agent.drop_buffered_data
      end

      def test_span_ids_passed_in_payload_when_span_events_enabled
        NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
        payload = nil
        external_segment = nil
        transaction = in_transaction('test_txn') do |txn|
          external_segment = NewRelic::Agent::Tracer.\
                       start_external_request_segment library: "net/http",
                                                      uri: "http://docs.newrelic.com",
                                                      procedure: "GET"
          payload = txn.distributed_tracer.create_distributed_trace_payload
        end

        assert_equal external_segment.guid, payload.id
        assert_equal transaction.guid, payload.transaction_id
      end

      def test_parent_span_id_propagated_cross_process
        NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
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
          txn.distributed_tracer.accept_distributed_trace_payload payload.text
        end

        last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
        txn2_entry_span = last_span_events.detect{ |ev| ev[0]["name"] == "test_txn2" }

        assert_equal external_segment.guid, txn2_entry_span[0]["parentId"]
      end

      def test_span_event_parenting
        txn_segment = nil
        segment_a = nil
        segment_b = nil
        txn = in_transaction('test_txn') do |t|
          t.stubs(:sampled?).returns(true)
          txn_segment = t.initial_segment
          segment_a = NewRelic::Agent::Tracer.start_segment(name: 'segment_a')
          segment_b = NewRelic::Agent::Tracer.start_segment(name: 'segment_b')
          segment_b.finish
          segment_a.finish
        end

        last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

        txn_segment_event, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "test_txn" }

        assert_equal txn.guid, txn_segment_event["transactionId"]
        assert_nil   txn_segment_event["parentId"]

        segment_event_a, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "segment_a" }

        assert_equal txn.guid, segment_event_a["transactionId"]
        assert_equal txn_segment.guid, segment_event_a["parentId"]

        segment_event_b, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "segment_b" }

        assert_equal txn.guid, segment_event_b["transactionId"]
        assert_equal segment_a.guid, segment_event_b["parentId"]
      end

      def test_entrypoint_attribute_added_to_first_span_only
        in_transaction('test_txn') do |t|
          t.stubs(:sampled?).returns(true)
          segment_a = NewRelic::Agent::Tracer.start_segment(name: 'segment_a')
          segment_a.finish
        end

        last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

        txn_segment_event, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "test_txn" }

        segment_event_a, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "segment_a" }

        assert txn_segment_event.key?('nr.entryPoint')
        assert txn_segment_event.fetch('nr.entryPoint')
        refute segment_event_a.key?('nr.entryPoint')
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
    end
  end
end
