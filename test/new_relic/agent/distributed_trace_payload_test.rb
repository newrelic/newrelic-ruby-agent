# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_trace_payload'
require 'new_relic/agent/transaction'
require 'net/http'

module NewRelic
  module Agent
    class DistributedTracePayloadTest < Minitest::Test

      def setup
        nr_freeze_time

        @config = {
          :'distributed_tracing.enabled' => true,
          :application_id => "46954",
          :cross_process_id => "190#222",
          :'span_events.enabled' => false
        }

        NewRelic::Agent.config.add_config_for_testing(@config)
      end

      def teardown
        NewRelic::Agent.config.remove_config(@config)
        NewRelic::Agent.config.reset_to_defaults
        NewRelic::Agent.drop_buffered_data
      end

      def test_payload_is_created_if_connected
        created_at, payload = nil, nil

        in_transaction "test_txn" do |txn|
          created_at = (Time.now.to_f * 1000).round
          payload = DistributedTracePayload.for_transaction txn
        end

        assert_equal "46954", payload.parent_app_id
        assert_equal "190", payload.parent_account_id
        assert_equal DistributedTracePayload::VERSION, payload.version
        assert_equal "App", payload.parent_type
        assert_equal created_at, payload.timestamp
      end

      def test_app_id_uses_fallback_if_not_explicity_set
        with_config cross_process_id: "190#46954", application_id: "" do
          payload = nil

          in_transaction "test_txn" do |txn|
            payload = DistributedTracePayload.for_transaction txn
          end

          assert_equal "46954", payload.parent_app_id
        end
      end


      def test_attributes_are_copied_from_transaction
        payload = nil

        transaction = in_transaction "test_txn" do |txn|
          payload = DistributedTracePayload.for_transaction txn
        end

        assert_equal transaction.guid, payload.transaction_id
        assert_equal transaction.trace_id, payload.trace_id
        assert_equal transaction.parent_id, payload.parent_id
        assert_equal transaction.priority, payload.priority
      end

      def test_sampled_flag_is_copied_from_transaction
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(false)
        in_transaction "test_txn" do |txn|
          payload = DistributedTracePayload.for_transaction txn
          assert_equal false, payload.sampled
        end

        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
        in_transaction "test_txn2" do |txn|
          payload = DistributedTracePayload.for_transaction txn
          assert_equal true, payload.sampled
        end
      end

      def test_payload_attributes_populated_from_serialized_version
        created_at = (Time.now.to_f * 1000).round

        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

        referring_transaction = in_transaction("test_txn") {}

        incoming_payload = DistributedTracePayload.for_transaction referring_transaction
        payload = DistributedTracePayload.from_json incoming_payload.to_json

        assert_equal DistributedTracePayload::VERSION, payload.version
        assert_equal "App", payload.parent_type
        assert_equal "46954", payload.parent_app_id
        assert_equal "190", payload.parent_account_id
        assert_equal referring_transaction.guid, payload.transaction_id
        assert_equal referring_transaction.parent_id, payload.parent_id
        assert_equal referring_transaction.trace_id, payload.trace_id
        assert_equal true, payload.sampled?
        assert_equal referring_transaction.priority, payload.priority
        assert_equal created_at.round, payload.timestamp
      end

      def test_payload_attributes_populated_from_html_safe_version
        created_at = (Time.now.to_f * 1000).round

        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

        referring_transaction = in_transaction("test_txn") {}

        incoming_payload = DistributedTracePayload.for_transaction referring_transaction
        payload = DistributedTracePayload.from_http_safe incoming_payload.http_safe

        assert_equal DistributedTracePayload::VERSION, payload.version
        assert_equal "App", payload.parent_type
        assert_equal "46954", payload.parent_app_id
        assert_equal "190", payload.parent_account_id
        assert_equal referring_transaction.guid, payload.transaction_id
        assert_equal referring_transaction.parent_id, payload.parent_id
        assert_equal referring_transaction.trace_id, payload.trace_id
        assert_equal true, payload.sampled?
        assert_equal referring_transaction.priority, payload.priority
        assert_equal created_at.round, payload.timestamp
      end

      def test_serialized_payload_has_expected_keys
        transaction = in_transaction("test_txn") {}
        payload = DistributedTracePayload.for_transaction transaction

        raw_payload = JSON.parse(payload.to_json)

        assert_equal_unordered %w(v d), raw_payload.keys
        assert_equal_unordered %w(ty ac ap pa id tx tr pr sa ti), raw_payload["d"].keys
      end

      def test_to_json_and_from_json_are_inverse_operations
        with_config :'span_events.enabled' => true do
          transaction = in_transaction("test_txn") {}
          payload1 = DistributedTracePayload.for_transaction(transaction)
          payload2 = DistributedTracePayload.from_json(payload1.to_json)

          payload1_ivars = payload1.instance_variables.map { |iv| payload1.instance_variable_get(iv) }
          payload2_ivars = payload2.instance_variables.map { |iv| payload2.instance_variable_get(iv) }

          assert_equal payload1_ivars, payload2_ivars
        end
      end
    end
  end
end
