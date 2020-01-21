# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

require 'new_relic/agent/messaging'
require 'new_relic/agent/transaction'

module NewRelic::Agent
  module DistributedTracing
    class DistributedTracerTest < Minitest::Test

      def teardown
        NewRelic::Agent::Transaction::TraceContext::AccountHelpers.instance_variable_set :@trace_state_entry_key, nil
        NewRelic::Agent.drop_buffered_data
      end

      def distributed_tracing_enabled
        {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled'      => true,
          :account_id => "190",
          :primary_application_id => "46954",
          :trusted_account_key => "trust_this!"
        }
      end

      def build_trace_context_header env={}
        env['HTTP_TRACEPARENT'] = '00-12345678901234567890123456789012-1234567890123456-00'
        env['HTTP_TRACESTATE'] = ''
        return env
      end

      def build_distributed_trace_header env={}
        begin
          NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
          with_config distributed_tracing_enabled do
            in_transaction "referring_txn" do |txn|
              payload = txn.distributed_tracer.create_distributed_trace_payload
              assert payload, "failed to build a distributed_trace payload!"
              env['HTTP_NEWRELIC'] = payload.http_safe
            end
          end
          return env
        ensure
          NewRelic::Agent::DistributedTracePayload.unstub(:connected?)
        end
      end

      def tests_accepts_trace_context_header
        env = build_trace_context_header
        refute env['HTTP_NEWRELIC']
        assert env['HTTP_TRACEPARENT']

        with_config(distributed_tracing_enabled) do
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            assert txn.distributed_tracer.trace_context_header_data, "expected a trace context header"
            refute txn.distributed_tracer.distributed_trace_payload, "refute a distributed_trace payload"
          end
        end
      end

      def tests_accepts_distributed_trace_header
        env = build_distributed_trace_header
        assert env['HTTP_NEWRELIC']
        refute env['HTTP_TRACEPARENT']

        with_config(distributed_tracing_enabled) do
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            refute txn.distributed_tracer.trace_context_header_data, "refute a trace context header"
            assert txn.distributed_tracer.distributed_trace_payload, "expected a distributed_trace payload"
          end
        end
      end

      def tests_ignores_distributed_trace_header_when_context_trace_header_present
        env = build_distributed_trace_header build_trace_context_header
        assert env['HTTP_NEWRELIC']
        assert env['HTTP_TRACEPARENT']

        with_config(distributed_tracing_enabled) do
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            assert txn.distributed_tracer.trace_context_header_data, "expected a trace context header"
            refute txn.distributed_tracer.distributed_trace_payload, "refute a distributed_trace payload"
          end
        end
      end

      def tests_does_not_crash_when_no_distributed_trace_headers_are_present
        in_transaction do |txn|
          txn.distributed_tracer.accept_incoming_request({})
          assert_nil txn.distributed_tracer.trace_context_header_data
          assert_nil txn.distributed_tracer.distributed_trace_payload
        end
      end

      def test_wrap_message_broker_consume_transaction_reads_cat_headers
        guid                 = "BEC1BC64675138B9"
        cross_process_id     = "321#123"
        intrinsic_attributes = { client_cross_process_id: cross_process_id, referring_transaction_guid: guid }
        obfuscated_id        = nil
        raw_txn_info         = nil
        obfuscated_txn_info  = nil

        tap = mock 'tap'
        tap.expects :tap

        with_config :"cross_application_tracer.enabled" => true,
                    :cross_process_id => cross_process_id,
                    :trusted_account_ids => [321],
                    :encoding_key => "abc" do

          in_transaction do |txn|
            obfuscated_id       = obfuscator.obfuscate cross_process_id
            raw_txn_info        = [guid, false, guid, txn.distributed_tracer.cat_path_hash]
            obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json
          end

          Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: 'Default',
            headers: { "NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info }
          ) do
            txn = NewRelic::Agent::Tracer.current_transaction
            ca_payload = txn.distributed_tracer.cross_app_payload
            assert_equal cross_process_id, ca_payload.id
            assert_equal ca_payload.referring_guid,      raw_txn_info[0]
            assert_equal ca_payload.referring_trip_id,   raw_txn_info[2]
            assert_equal ca_payload.referring_path_hash, raw_txn_info[3]
            assert_equal txn.attributes.intrinsic_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER), intrinsic_attributes
            tap.tap
          end
        end
      end

      def test_wrap_message_broker_consume_transaction_reads_synthetics_and_cat_headers
        cross_process_id     = "321#123"
        guid                 = "BEC1BC64675138B9"
        obfuscated_id        = nil
        raw_txn_info         = nil
        obfuscated_txn_info  = nil

        synthetics_payload   = [1, 321, 'abc', 'def', 'ghe']
        synthetics_header    = nil

        tap = mock 'tap'
        tap.expects :tap

        with_config :"cross_application_tracer.enabled" => true,
                    :cross_process_id => cross_process_id,
                    :trusted_account_ids => [321],
                    :encoding_key => "abc" do

          in_transaction "test_txn" do |txn|
            obfuscated_id = obfuscator.obfuscate cross_process_id
            raw_txn_info = [guid, false, guid, txn.distributed_tracer.cat_path_hash]
            obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json
            synthetics_header = obfuscator.obfuscate synthetics_payload.to_json
          end

          Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: "Default",
            headers: {
              "NewRelicID" => obfuscated_id,
              "NewRelicTransaction" => obfuscated_txn_info,
              "NewRelicSynthetics" => synthetics_header
            }
          ) do
            txn = Tracer.current_transaction
            cat_payload = txn.distributed_tracer.cross_app_payload
            assert_equal cross_process_id, cat_payload.id
            assert_equal cat_payload.referring_guid,      raw_txn_info[0]
            assert_equal cat_payload.referring_trip_id,   raw_txn_info[2]
            assert_equal cat_payload.referring_path_hash, raw_txn_info[3]
            assert_equal synthetics_header, txn.raw_synthetics_header
            assert_equal synthetics_payload, txn.synthetics_payload
            tap.tap
          end

        end
      end

      def test_wrap_message_broker_consume_transaction_reads_distributed_trace_headers
        tap = mock 'tap'
        tap.expects :tap

        DistributedTracePayload.stubs(:connected?).returns(true)
        with_config :"cross_application_tracer.enabled" => false,
                    :"distributed_tracing.enabled" => true,
                    :account_id => "190",
                    :primary_application_id => "46954",
                    :trusted_account_key => "trust_this!" do

          payload = nil
          parent = in_transaction do |txn|
            payload = txn.distributed_tracer.create_distributed_trace_payload
          end

          Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: 'Default',
            headers: {'Newrelic' => Base64.strict_encode64(payload.text)}
          ) do
            Tracer.current_transaction
            tap.tap
          end

          intrinsics, _, _ = last_transaction_event

          assert_equal parent.guid, intrinsics['parentId']
        end
      end

      def test_wrap_message_broker_consume_transaction_records_proper_metrics_with_cat
        guid                 = "BEC1BC64675138B9"
        cross_process_id     = "321#123"
        obfuscated_id        = nil
        raw_txn_info         = nil
        obfuscated_txn_info  = nil

        tap = mock 'tap'
        tap.expects :tap

        with_config :"cross_application_tracer.enabled" => true,
                    :cross_process_id => cross_process_id,
                    :trusted_account_ids => [321],
                    :encoding_key => "abc" do

          in_transaction "test_txn" do |txn|
            obfuscated_id = obfuscator.obfuscate cross_process_id
            raw_txn_info = [guid, false, guid, txn.distributed_tracer.cat_path_hash]
            obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json
          end

          Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: "Default",
            headers: {"NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info }
          ) do
            tap.tap
          end

          assert_metrics_recorded "ClientApplication/#{cross_process_id}/all"
        end
      end

      def obfuscator
        NewRelic::Agent::CrossAppTracing.obfuscator
      end
    end
  end
end
