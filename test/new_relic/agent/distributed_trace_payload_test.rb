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
        freeze_time
      end

      def teardown
        NewRelic::Agent.drop_buffered_data
      end

      def test_payload_is_created_if_connected
        with_config application_id: "46954", cross_process_id: "190#222" do
          state = TransactionState.tl_get

          transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          created_at = (Time.now.to_f * 1000).round
          payload = DistributedTracePayload.for_transaction transaction
          Transaction.stop state

          assert_equal "46954", payload.caller_app_id
          assert_equal "190", payload.caller_account_id
          assert_equal [0, 0], payload.version
          assert_equal "App", payload.caller_type
          assert_equal created_at, payload.timestamp
        end
      end

      def test_app_id_uses_fallback_if_not_explicity_set
        with_config cross_process_id: "190#46954" do
          payload = nil

          in_transaction "test_txn" do |txn|
            payload = DistributedTracePayload.for_transaction txn
          end

          assert_equal "46954", payload.caller_app_id
        end
      end


      def test_attributes_are_copied_from_transaction
        with_config application_id: "46954", cross_process_id: "190#222" do
          state = TransactionState.tl_get

          transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          payload = DistributedTracePayload.for_transaction transaction
          Transaction.stop state

          assert_equal transaction.guid, payload.id
          assert_equal transaction.distributed_tracing_trip_id, payload.trip_id
          assert_equal transaction.parent_ids, payload.parent_ids
          assert_equal transaction.depth + 1, payload.depth
          assert_equal transaction.order, payload.order
        end
      end

      def test_sampled_flag_is_copied_from_transaction
        with_config application_id: "46954", cross_process_id: "190#222" do

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(false)
          in_transaction "test_txn" do |txn|
            payload = DistributedTracePayload.for_transaction txn
            assert_equal false, payload.sampled
          end

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          in_transaction "test_txn2" do |txn|
            payload = DistributedTracePayload.for_transaction txn
            assert_equal true, payload.sampled
          end
        end
      end

      def test_attributes_synthetics_attributes_are_copied_when_present
        with_config application_id: "46954", cross_process_id: "190#222" do
          state = TransactionState.tl_get

          transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          transaction.synthetics_payload = [1, 1, 100, 200, 300]

          payload = DistributedTracePayload.for_transaction transaction
          Transaction.stop state

          assert_equal 100, payload.synthetics_resource
          assert_equal 200, payload.synthetics_job
          assert_equal 300, payload.synthetics_monitor
        end
      end

      def test_host_copied_from_uri
        with_config application_id: "46954", cross_process_id: "190#222" do
          state = TransactionState.tl_get

          transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          payload = DistributedTracePayload.for_transaction transaction, URI("http://newrelic.com/blog")
          Transaction.stop state

          assert_equal "newrelic.com", payload.host
        end
      end

      def test_payload_attributes_populated_from_serialized_version
        incoming_payload = nil
        referring_transaction = nil
        created_at = (Time.now.to_f * 1000).round

        with_config application_id: "46954", cross_process_id: "190#222" do
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          state = TransactionState.tl_get

          referring_transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          referring_transaction.synthetics_payload = [1, 1, 100, 200, 300]
          Transaction.stop state

          incoming_payload = DistributedTracePayload.for_transaction referring_transaction, URI("http://newrelic.com/blog")
        end

        payload = DistributedTracePayload.from_json incoming_payload.to_json

        assert_equal [0, 0], payload.version
        assert_equal "App", payload.caller_type
        assert_equal "46954", payload.caller_app_id
        assert_equal "190", payload.caller_account_id
        assert_equal referring_transaction.guid, payload.id
        assert_equal referring_transaction.distributed_tracing_trip_id, payload.trip_id
        assert_equal true, payload.sampled?
        assert_equal referring_transaction.parent_ids, payload.parent_ids
        assert_equal referring_transaction.depth + 1, payload.depth
        assert_equal referring_transaction.order, payload.order
        assert_equal created_at.round, payload.timestamp
        assert_equal "newrelic.com", payload.host
        assert_equal 100, payload.synthetics_resource
        assert_equal 200, payload.synthetics_job
        assert_equal 300, payload.synthetics_monitor
      end

      def test_payload_attributes_populated_from_html_safe_version
        incoming_payload = nil
        referring_transaction = nil
        created_at = (Time.now.to_f * 1000).round

        with_config application_id: "46954", cross_process_id: "190#222" do
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          state = TransactionState.tl_get

          referring_transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          referring_transaction.synthetics_payload = [1, 1, 100, 200, 300]
          Transaction.stop state

          incoming_payload = DistributedTracePayload.for_transaction referring_transaction, URI("http://newrelic.com/blog")
        end

        payload = DistributedTracePayload.from_http_safe incoming_payload.http_safe

        assert_equal [0, 0], payload.version
        assert_equal "App", payload.caller_type
        assert_equal "46954", payload.caller_app_id
        assert_equal "190", payload.caller_account_id
        assert_equal referring_transaction.guid, payload.id
        assert_equal referring_transaction.distributed_tracing_trip_id, payload.trip_id
        assert_equal true, payload.sampled?
        assert_equal referring_transaction.parent_ids, payload.parent_ids
        assert_equal referring_transaction.depth + 1, payload.depth
        assert_equal referring_transaction.order, payload.order
        assert_equal created_at.round, payload.timestamp
        assert_equal "newrelic.com", payload.host
        assert_equal 100, payload.synthetics_resource
        assert_equal 200, payload.synthetics_job
        assert_equal 300, payload.synthetics_monitor
      end
    end
  end
end
