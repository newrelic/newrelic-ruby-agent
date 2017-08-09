# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_trace_payload'
require 'new_relic/agent/transaction'
require 'net/http'

module NewRelic
  module Agent
    class Transaction
      class DistributedTracingTest < Minitest::Test
        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_create_distributed_trace_payload_returns_payload_incrs_order
          with_config application_id: "46954", cross_process_id: "190#222" do
            freeze_time
            created_at = Time.now.to_f
            state = TransactionState.tl_get

            transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
            payload = transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
            Transaction.stop(state)

            assert_equal 1, transaction.order
            assert_equal "46954", payload.caller_app_id
            assert_equal "190", payload.caller_account_id
            assert_equal [2, 0], payload.version
            assert_equal "App", payload.caller_type
            assert_equal transaction.guid, payload.id
            assert_equal transaction.distributed_tracing_trip_id, payload.trip_id
            assert_equal transaction.parent_ids, payload.parent_ids
            assert_equal transaction.depth, payload.depth
            assert_equal transaction.order, payload.order
            assert_equal "newrelic.com", payload.host
            assert_equal created_at, payload.timestamp

            transaction.create_distributed_trace_payload
            assert_equal 2, transaction.order
          end
        end

        def test_accept_distributed_trace_payload_assigns_json_payload
          payload = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction do |txn|
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          transaction = in_transaction "test_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
          end

          refute_nil transaction.inbound_distributed_trace_payload

          assert_equal transaction.depth, payload.depth + 1
          assert_equal transaction.distributed_tracing_trip_id, payload.trip_id
        end

        def test_accept_distributed_trace_payload_assigns_http_safe_payload
          payload = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction do |txn|
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          transaction = in_transaction "test_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.http_safe
          end

          refute_nil transaction.inbound_distributed_trace_payload

          assert_equal transaction.depth, payload.depth + 1
          assert_equal transaction.distributed_tracing_trip_id, payload.trip_id
        end

        def test_instrinsics_assigned_to_transaction_event_from_disributed_trace
          payload = nil
          referring_transaction = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction "test_txn" do |txn|
              referring_transaction = txn
              payload = referring_transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          transaction = in_transaction "text_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
          end

          intrinsics, _, _ = last_transaction_event

          inbound_payload = transaction.inbound_distributed_trace_payload

          assert_equal inbound_payload.caller_type, intrinsics["caller.type"]
          assert_equal inbound_payload.caller_transport_type, intrinsics["caller.transportType"]
          assert_equal inbound_payload.caller_app_id, intrinsics["caller.app"]
          assert_equal inbound_payload.caller_account_id, intrinsics["caller.account"]
          assert_equal inbound_payload.host, intrinsics["caller.host"]
          assert_equal inbound_payload.depth, intrinsics["nr.depth"]
          assert_equal inbound_payload.order, intrinsics["nr.order"]
          assert_equal referring_transaction.guid, intrinsics["nr.referringTransactionGuid"]
          assert_equal inbound_payload.id, referring_transaction.guid
          assert_equal inbound_payload.trip_id, intrinsics["nr.tripId"]
          assert_equal transaction.guid, intrinsics["nr.guid"]
          assert_equal inbound_payload.parent_ids.first, intrinsics["nr.parentIds"]
        end

        def test_instrinsics_assigned_to_error_event_from_disributed_trace
          payload = nil
          referring_transaction = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction "test_txn" do |txn|
              referring_transaction = txn
              payload = referring_transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          transaction = in_transaction "text_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
            NewRelic::Agent.notice_error StandardError.new "Nooo!"
          end

          intrinsics, _, _ = last_error_event

          inbound_payload = transaction.inbound_distributed_trace_payload

          assert_equal inbound_payload.caller_type, intrinsics["caller.type"]
          assert_equal inbound_payload.caller_transport_type, intrinsics["caller.transportType"]
          assert_equal inbound_payload.caller_app_id, intrinsics["caller.app"]
          assert_equal inbound_payload.caller_account_id, intrinsics["caller.account"]
          assert_equal inbound_payload.host, intrinsics["caller.host"]
          assert_equal inbound_payload.depth, intrinsics["nr.depth"]
          assert_equal inbound_payload.order, intrinsics["nr.order"]
          assert_equal referring_transaction.guid, intrinsics["nr.referringTransactionGuid"]
          assert_equal inbound_payload.id, referring_transaction.guid
          assert_equal transaction.guid, intrinsics["nr.transactionGuid"]
          assert_equal inbound_payload.trip_id, intrinsics["nr.tripId"]
          assert_equal inbound_payload.parent_ids.first, intrinsics["nr.parentIds"]
        end
      end
    end
  end
end
