# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)

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
      end

      def teardown
        NewRelic::Agent.config.remove_config(@config)
        NewRelic::Agent.config.reset_to_defaults
        NewRelic::Agent.drop_buffered_data
      end

      def test_span_ids_passed_in_payload_when_span_events_enabled
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(false)
        payload = nil
        external_segment = nil
        transaction = in_transaction('test_txn') do |txn|
          external_segment = NewRelic::Agent::Transaction.\
                       start_external_request_segment library: "net/http",
                                                      uri: "http://docs.newrelic.com",
                                                      procedure: "GET"
          payload = txn.create_distributed_trace_payload
        end

        assert_equal external_segment.guid, payload.id
        assert_equal transaction.guid, payload.transaction_id
      end

      def test_parent_span_id_propagated_cross_process
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
        payload = nil
        external_segment = nil
        in_transaction('test_txn') do |txn|
          external_segment = NewRelic::Agent::Transaction.\
                       start_external_request_segment library: "net/http",
                                                      uri: "http://docs.newrelic.com",
                                                      procedure: "GET"
          payload = txn.create_distributed_trace_payload
        end

        in_transaction('test_txn2') do |txn|
          txn.accept_distributed_trace_payload payload.to_json
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
          segment_a = NewRelic::Agent::Transaction.start_segment(name: 'segment_a')
          segment_b = NewRelic::Agent::Transaction.start_segment(name: 'segment_b')
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
        txn_segment = nil
        segment_a = nil
        in_transaction('test_txn') do |t|
          t.stubs(:sampled?).returns(true)
          txn_segment = t.initial_segment
          segment_a = NewRelic::Agent::Transaction.start_segment(name: 'segment_a')
          segment_a.finish
        end

        last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

        txn_segment_event, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "test_txn" }

        segment_event_a, _, _ = last_span_events.detect { |ev| ev[0]["name"] == "segment_a" }

        assert txn_segment_event.key?('nr.entryPoint')
        assert txn_segment_event.fetch('nr.entryPoint')
        refute segment_event_a.key?('nr.entryPoint')
      end
    end
  end
end
