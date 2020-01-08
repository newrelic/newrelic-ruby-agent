# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

require 'new_relic/agent/messaging'
require 'new_relic/agent/transaction'

module NewRelic::Agent
  module DistributedTracing
    class InterfaceTest < Minitest::Test

      def teardown
        NewRelic::Agent.drop_buffered_data
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
            raw_txn_info        = [guid, false, guid, txn.cat_path_hash]
            obfuscated_txn_info = obfuscator.obfuscate raw_txn_info.to_json
          end

          Messaging.wrap_message_broker_consume_transaction(
            library: "RabbitMQ",
            destination_type: :exchange,
            destination_name: 'Default',
            headers: { "NewRelicID" => obfuscated_id, "NewRelicTransaction" => obfuscated_txn_info }
          ) do
            txn = NewRelic::Agent::Tracer.current_transaction
            assert_equal cross_process_id, txn.cross_app_payload.id
            assert_equal txn.cross_app_payload.referring_guid,      raw_txn_info[0]
            assert_equal txn.cross_app_payload.referring_trip_id,   raw_txn_info[2]
            assert_equal txn.cross_app_payload.referring_path_hash, raw_txn_info[3]
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
            raw_txn_info = [guid, false, guid, txn.cat_path_hash]
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
            assert_equal cross_process_id, txn.cross_app_payload.id
            assert_equal txn.cross_app_payload.referring_guid,      raw_txn_info[0]
            assert_equal txn.cross_app_payload.referring_trip_id,   raw_txn_info[2]
            assert_equal txn.cross_app_payload.referring_path_hash, raw_txn_info[3]
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
            payload = txn.create_distributed_trace_payload
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
            raw_txn_info = [guid, false, guid, txn.cat_path_hash]
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