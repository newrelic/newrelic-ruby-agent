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
            created_at = (Time.now.to_f * 1000).round
            state = TransactionState.tl_get

            transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
            payload = transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
            Transaction.stop(state)

            assert_equal 1, transaction.order
            assert_equal "46954", payload.caller_app_id
            assert_equal "190", payload.caller_account_id
            assert_equal [0, 0], payload.version
            assert_equal "App", payload.caller_type
            assert_equal transaction.guid, payload.id
            assert_equal transaction.distributed_tracing_trip_id, payload.trip_id
            assert_equal transaction.parent_ids, payload.parent_ids
            assert_equal transaction.depth + 1, payload.depth
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

          assert_equal transaction.depth, payload.depth
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

          assert_equal transaction.depth, payload.depth
          assert_equal transaction.distributed_tracing_trip_id, payload.trip_id
        end

        def test_sampled_flag_propagated_when_true_in_incoming_payload
          payload = nil

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction do |txn|
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(false)

          in_transaction "test_txn2" do |txn|
            refute txn.sampled?
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
            assert txn.sampled?
          end
        end

        def test_sampled_flag_respects_upstreams_decision_when_sampled_is_false
          payload = nil

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(false)

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction do |txn|
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)

          in_transaction "test_txn2" do |txn|
            assert txn.sampled?
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
            refute txn.sampled?
          end
        end

        def test_proper_intrinsics_assigned_for_first_app_in_distributed_trace
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          guid = nil
          payload = nil
          transaction = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            transaction = in_transaction "test_txn" do |txn|
              guid = txn.guid
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          intrinsics, _, _ = last_transaction_event

          assert_equal guid, intrinsics['nr.tripId']
          assert_equal [guid], intrinsics['nr.parentIds']
          assert_equal 1, intrinsics['nr.depth']
          assert_nil intrinsics['nr.order']
          assert intrinsics['nr.sampled']

          txn_intrinsics = transaction.attributes.intrinsic_attributes_for AttributeFilter::DST_TRANSACTION_TRACER

          assert_equal guid, txn_intrinsics['nr.tripId']
          assert_equal [guid], txn_intrinsics['nr.parentIds']
          assert_equal 1, txn_intrinsics['nr.depth']
          assert_nil txn_intrinsics['nr.order']
          assert txn_intrinsics[:'nr.sampled']
        end

        def test_initial_legacy_cat_request_trip_id_overwritten_by_first_distributed_trace_guid
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          transaction = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            transaction = in_transaction "test_txn" do |txn|
              #simulate legacy cat
              state = TransactionState.tl_get
              state.referring_transaction_info = [
                "b854df4feb2b1f06",
                false,
                "7e249074f277923d",
                "5d2957be"
              ]
              txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          intrinsics, _, _ = last_transaction_event
          assert_equal transaction.guid, intrinsics['nr.tripId']

          txn_intrinsics = transaction.attributes.intrinsic_attributes_for AttributeFilter::DST_TRANSACTION_TRACER
          assert_equal transaction.guid, txn_intrinsics['nr.tripId']
        end

        def test_instrinsics_assigned_to_transaction_event_from_disributed_trace
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
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
          assert_equal true, intrinsics["nr.sampled"]
          assert_equal inbound_payload.parent_ids.first, intrinsics["nr.parentIds"]
        end

        def test_sampled_is_false_in_transaction_event_when_indicated_by_upstream
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          payload = nil
          referring_transaction = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction "test_txn" do |txn|
              referring_transaction = txn
              payload = referring_transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
              payload.sampled = false
            end
          end

          in_transaction "text_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
          end

          intrinsics, _, _ = last_transaction_event
          assert_equal false, intrinsics["nr.sampled"]
        end

        def test_instrinsics_assigned_to_error_event_from_disributed_trace
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
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
          assert_equal true, intrinsics["nr.sampled"]
          assert_equal inbound_payload.parent_ids.first, intrinsics["nr.parentIds"]
        end

        def test_sampled_is_false_in_error_event_when_indicated_by_upstream
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          payload = nil
          referring_transaction = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction "test_txn" do |txn|
              referring_transaction = txn
              payload = referring_transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
              payload.sampled = false
            end
          end

          in_transaction "text_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
            NewRelic::Agent.notice_error StandardError.new "Nooo!"
          end

          intrinsics, _, _ = last_error_event
          assert_equal false, intrinsics["nr.sampled"]
        end

        def test_distributed_trace_does_not_propagate_nil_sampled_flags
          payload = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction do |txn|
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)
          payload.sampled = nil

          transaction = in_transaction "test_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
          end

          intrinsics, _, _ = last_transaction_event

          assert_equal true, transaction.sampled?
          assert_equal true, intrinsics["nr.sampled"]
        end

        def test_sampled_flag_added_to_intrinsics_without_distributed_trace_when_true
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)

          transaction = in_transaction("test_txn") do
            NewRelic::Agent.notice_error StandardError.new("Sorry!")
          end

          txn_intrinsics, _, _ = last_transaction_event
          err_intrinsics, _, _ = last_error_event

          assert_equal true, transaction.sampled?
          assert_equal true, txn_intrinsics["nr.sampled"]
          assert_equal true, err_intrinsics["nr.sampled"]
        end

        def test_sampled_flag_added_to_intrinsics_without_distributed_trace_when_false
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(false)

          transaction = in_transaction("test_txn") do
            NewRelic::Agent.notice_error StandardError.new("Sorry!")
          end

          txn_intrinsics, _, _ = last_transaction_event
          err_intrinsics, _, _ = last_error_event

          assert_equal false, transaction.sampled?
          assert_equal false, txn_intrinsics["nr.sampled"]
          assert_equal false, err_intrinsics["nr.sampled"]
        end

        def test_order_sent_in_payloads_reflects_counter_on_transaction
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(false)

          in_transaction("test_txn") do |txn|
            1.upto(3) do |i|
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
              assert_equal i, payload.order
            end
          end
        end

        def test_order_sent_on_txn_event_reflects_order_on_incoming_payload
          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(false)
          payload = nil

          with_config application_id: "46954", cross_process_id: "190#222" do
            in_transaction do |txn|
              payload = txn.create_distributed_trace_payload URI("http://newrelic.com/blog")
            end
          end

          payload.order = 5

          NewRelic::Agent.instance.throughput_monitor.stubs(:sampled?).returns(true)

          in_transaction "test_txn2" do |txn|
            txn.accept_distributed_trace_payload "HTTP", payload.to_json
          end

          intrinsics, _, _ = last_transaction_event
          assert_equal 5, intrinsics['nr.order']
        end
      end
    end
  end
end
