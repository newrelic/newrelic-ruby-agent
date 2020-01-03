# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

require 'new_relic/agent/distributed_tracing/distributed_trace_payload'
require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class DistributedTracePayloadTest < Minitest::Test

      def setup
        nr_freeze_time
        NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)


        @config = {
          :'distributed_tracing.enabled' => true,
          :account_id => "190",
          :primary_application_id => "46954",
          :trusted_account_key => "trust_this!"
        }
        NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
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
        assert_equal "trust_this!", payload.trusted_account_key
        assert_equal DistributedTracePayload::VERSION, payload.version
        assert_equal "App", payload.parent_type
        assert_equal created_at, payload.timestamp
      end

      def test_trusted_account_id_present_if_different_than_account_id
        payload = nil
        in_transaction "test_txn" do |txn|
          payload = DistributedTracePayload.for_transaction txn
        end

        assert_equal "trust_this!", payload.trusted_account_key

        deserialized_payload = JSON.parse(payload.text)

        assert_equal "trust_this!", deserialized_payload["d"]["tk"]
      end

      def test_trusted_account_id_not_present_if_it_matches_account_id
        with_config :trusted_account_key => "190" do
          payload = nil
          in_transaction "test_txn" do |txn|
            payload = DistributedTracePayload.for_transaction txn
          end

          assert_nil payload.trusted_account_key

          deserialized_payload = JSON.parse(payload.text)

          refute deserialized_payload["d"].key? "tk"
        end
      end

      def test_attributes_are_copied_from_transaction
        payload = nil

        transaction = in_transaction "test_txn" do |txn|
          payload = DistributedTracePayload.for_transaction txn
        end

        assert_equal transaction.guid, payload.transaction_id
        assert_equal transaction.trace_id, payload.trace_id
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

        incoming_payload = nil

        referring_transaction = in_transaction("test_txn") do |txn|
          incoming_payload = txn.create_distributed_trace_payload
        end

        payload = DistributedTracePayload.from_json incoming_payload.text

        assert_equal DistributedTracePayload::VERSION, payload.version
        assert_equal "App", payload.parent_type
        assert_equal "46954", payload.parent_app_id
        assert_equal "190", payload.parent_account_id
        assert_equal "trust_this!", payload.trusted_account_key
        assert_equal referring_transaction.initial_segment.guid, payload.id
        assert_equal referring_transaction.guid, payload.transaction_id
        assert_equal referring_transaction.trace_id, payload.trace_id
        assert_equal true, payload.sampled?
        assert_equal referring_transaction.priority, payload.priority
        assert_equal created_at.round, payload.timestamp
      end

      def test_payload_attributes_populated_from_html_safe_version
        created_at = (Time.now.to_f * 1000).round

        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

        incoming_payload = nil

        referring_transaction = in_transaction("test_txn") do |txn|
          incoming_payload = txn.create_distributed_trace_payload
        end

        payload = DistributedTracePayload.from_http_safe incoming_payload.http_safe

        assert_equal DistributedTracePayload::VERSION, payload.version
        assert_equal "App", payload.parent_type
        assert_equal "46954", payload.parent_app_id
        assert_equal "190", payload.parent_account_id
        assert_equal "trust_this!", payload.trusted_account_key
        assert_equal referring_transaction.initial_segment.guid, payload.id
        assert_equal referring_transaction.guid, payload.transaction_id
        assert_equal referring_transaction.trace_id, payload.trace_id
        assert_equal true, payload.sampled?
        assert_equal referring_transaction.priority, payload.priority
        assert_equal created_at.round, payload.timestamp
      end

      def test_serialized_payload_has_expected_keys
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
        payload = nil

        in_transaction("test_txn") do |txn|
          payload = DistributedTracePayload.for_transaction txn
        end

        raw_payload = JSON.parse(payload.text)

        assert_equal_unordered %w(v d), raw_payload.keys
        assert_equal_unordered %w(ty ac ap tk id tx tr pr sa ti), raw_payload["d"].keys
      end

      def test_to_json_and_from_json_are_inverse_operations
        transaction = in_transaction("test_txn") {}
        payload1 = DistributedTracePayload.for_transaction(transaction)
        payload2 = DistributedTracePayload.from_json(payload1.text)

        payload1_ivars = payload1.instance_variables.map { |iv| payload1.instance_variable_get(iv) }
        payload2_ivars = payload2.instance_variables.map { |iv| payload2.instance_variable_get(iv) }

        assert_equal payload1_ivars, payload2_ivars
      end
    end
  end
end
