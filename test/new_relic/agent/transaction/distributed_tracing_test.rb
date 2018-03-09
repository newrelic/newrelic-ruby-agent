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
        def setup
          NewRelic::Agent.config.add_config_for_testing(
            :'distributed_tracing.enabled' => true,
            :application_id => "46954",
            :cross_process_id => "190#222",
            :trusted_account_ids => [190],
          )
        end

        def teardown
          NewRelic::Agent.config.reset_to_defaults
          NewRelic::Agent.drop_buffered_data
        end

        def test_create_distributed_trace_payload_returns_payload
          nr_freeze_time
          created_at = (Time.now.to_f * 1000).round
          state = TransactionState.tl_get

          transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          payload = transaction.create_distributed_trace_payload
          Transaction.stop(state)

          assert_equal "46954", payload.caller_app_id
          assert_equal "190", payload.caller_account_id
          assert_equal [0, 0], payload.version
          assert_equal "App", payload.parent_type
          assert_equal transaction.guid, payload.id
          assert_equal transaction.distributed_trace_trip_id, payload.trip_id
          assert_nil   payload.parent_id
          assert_equal created_at, payload.timestamp
        end

        def test_accept_distributed_trace_payload_assigns_json_payload
          payload = create_distributed_trace_payload

          transaction = in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
          end

          refute_nil transaction.distributed_trace_payload

          assert_equal transaction.distributed_trace_trip_id, payload.trip_id
        end

        def test_accept_distributed_trace_payload_assigns_http_safe_payload
          payload = create_distributed_trace_payload

          transaction = in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.http_safe
          end

          refute_nil transaction.distributed_trace_payload

          assert_equal transaction.distributed_trace_trip_id, payload.trip_id
        end

        def test_accept_distributed_trace_payload_rejects_untrusted_account
          payload = create_distributed_trace_payload

          transaction = nil
          accepted    = nil
          with_config(trusted_account_ids: []) do
            transaction = in_transaction "test_txn" do |txn|
              accepted = txn.accept_distributed_trace_payload payload.http_safe
            end
          end

          assert_nil              transaction.distributed_trace_payload
          assert_false            accepted
          assert_metrics_recorded ['Supportability/DistributedTrace/AcceptPayload/Ignored/UntrustedAccount']
        end

        def test_sampled_flag_propagated_when_true_in_incoming_payload
          payload = create_distributed_trace_payload(sampled: true)

          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(false)

          in_transaction "test_txn" do |txn|
            refute txn.sampled?
            txn.accept_distributed_trace_payload payload.to_json
            assert txn.sampled?
          end
        end

        def test_sampled_flag_respects_upstreams_decision_when_sampled_is_false
          payload = create_distributed_trace_payload(sampled: false)

          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          in_transaction "test_txn" do |txn|
            assert txn.sampled?
            txn.accept_distributed_trace_payload payload.to_json
            refute txn.sampled?
          end
        end

        def test_proper_intrinsics_assigned_for_first_app_in_distributed_trace
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          result      = create_distributed_transactions
          transaction = result[:grandparent_transaction]
          payload     = result[:grandparent_payload]
          intrinsics  = result[:grandparent_intrinsics]

          assert_equal transaction.guid, intrinsics['nr.tripId']
          assert_nil                     intrinsics['nr.parentId']
          assert_nil                     intrinsics['nr.grandparentId']
          assert                         intrinsics['nr.sampled']

          txn_intrinsics = transaction.attributes.intrinsic_attributes_for AttributeFilter::DST_TRANSACTION_TRACER

          assert_equal transaction.guid, txn_intrinsics['nr.tripId']
          assert_nil                     txn_intrinsics['nr.parentId']
          assert_nil                     txn_intrinsics['nr.grandparentId']
          assert                         txn_intrinsics[:'nr.sampled']
        end

        def test_initial_legacy_cat_request_trip_id_overwritten_by_first_distributed_trace_guid
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
          transaction = nil

          transaction = in_transaction "test_txn" do |txn|
            #simulate legacy cat
            state = TransactionState.tl_get
            state.referring_transaction_info = [
              "b854df4feb2b1f06",
              false,
              "7e249074f277923d",
              "5d2957be"
            ]
            txn.create_distributed_trace_payload
          end

          intrinsics, _, _ = last_transaction_event
          assert_equal transaction.guid, intrinsics['nr.tripId']

          txn_intrinsics = transaction.attributes.intrinsic_attributes_for AttributeFilter::DST_TRANSACTION_TRACER
          assert_equal transaction.guid, txn_intrinsics['nr.tripId']
        end

        def test_intrinsics_assigned_to_transaction_event_from_disributed_trace
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          result                  = create_distributed_transactions
          grandparent_payload     = result[:grandparent_payload]
          grandparent_transaction = result[:grandparent_transaction]
          parent_payload          = result[:parent_payload]
          parent_transaction      = result[:parent_transaction]
          child_transaction       = result[:child_transaction]
          child_intrinsics        = result[:child_intrinsics]

          inbound_payload = child_transaction.distributed_trace_payload

          assert_equal inbound_payload.parent_type,           child_intrinsics["parent.type"]
          assert_equal inbound_payload.caller_transport_type, child_intrinsics["caller.transportType"]
          assert_equal inbound_payload.caller_app_id,         child_intrinsics["caller.app"]
          assert_equal inbound_payload.caller_account_id,     child_intrinsics["caller.account"]

          assert_equal parent_transaction.guid,               child_intrinsics["nr.referringTransactionGuid"]
          assert_equal inbound_payload.trip_id,               child_intrinsics["nr.tripId"]
          assert_equal child_transaction.guid,                child_intrinsics["nr.guid"]
          assert_equal true,                                  child_intrinsics["nr.sampled"]

          assert                                              child_intrinsics["nr.parentId"]
          assert_equal inbound_payload.parent_id,             child_intrinsics["nr.parentId"]

          assert                                              child_intrinsics["nr.grandparentId"]
          assert_equal inbound_payload.grandparent_id,        child_intrinsics["nr.grandparentId"]

          # Make sure the parent / grandparent links are connected all
          # the way up.
          #
          assert_equal inbound_payload.id,                    parent_transaction.guid
          assert_equal inbound_payload.grandparent_id,        parent_payload.parent_id
          assert_equal inbound_payload.grandparent_id,        grandparent_payload.id
        end

        def test_sampled_is_false_in_transaction_event_when_indicated_by_upstream
          payload = create_distributed_trace_payload(sampled: false)

          in_transaction "text_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
          end

          intrinsics, _, _ = last_transaction_event
          assert_equal false, intrinsics["nr.sampled"]
        end

        def test_intrinsics_assigned_to_error_event_from_disributed_trace
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
          payload = nil
          referring_transaction = nil

          in_transaction "test_txn" do |txn|
            referring_transaction = txn
            payload = referring_transaction.create_distributed_trace_payload
          end

          transaction = in_transaction "text_txn2" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
            NewRelic::Agent.notice_error StandardError.new "Nooo!"
          end

          intrinsics, _, _ = last_error_event

          inbound_payload = transaction.distributed_trace_payload

          assert_equal inbound_payload.parent_type, intrinsics["parent.type"]
          assert_equal inbound_payload.caller_transport_type, intrinsics["caller.transportType"]
          assert_equal inbound_payload.caller_app_id, intrinsics["caller.app"]
          assert_equal inbound_payload.caller_account_id, intrinsics["caller.account"]
          assert_equal referring_transaction.guid, intrinsics["nr.referringTransactionGuid"]
          assert_equal inbound_payload.id, referring_transaction.guid
          assert_equal transaction.guid, intrinsics["nr.transactionGuid"]
          assert_equal inbound_payload.trip_id, intrinsics["nr.tripId"]
          assert_equal true, intrinsics["nr.sampled"]
          assert       intrinsics["nr.parentId"], "Child should be linked to parent transaction"
          assert_equal inbound_payload.parent_id, intrinsics["nr.parentId"]
        end

        def test_sampled_is_false_in_error_event_when_indicated_by_upstream
          payload = create_distributed_trace_payload(sampled: false)

          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          in_transaction "text_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
            NewRelic::Agent.notice_error StandardError.new "Nooo!"
          end

          intrinsics, _, _ = last_error_event
          assert_equal false, intrinsics["nr.sampled"]
        end

        def test_distributed_trace_does_not_propagate_nil_sampled_flags
          payload = create_distributed_trace_payload
          payload.sampled = nil

          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          transaction = in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
          end

          intrinsics, _, _ = last_transaction_event

          assert_equal true, transaction.sampled?
          assert_equal true, intrinsics["nr.sampled"]
        end

        def test_sampled_flag_added_to_intrinsics_without_distributed_trace_when_true
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

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
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(false)

          transaction = in_transaction("test_txn") do
            NewRelic::Agent.notice_error StandardError.new("Sorry!")
          end

          txn_intrinsics, _, _ = last_transaction_event
          err_intrinsics, _, _ = last_error_event

          assert_equal false, transaction.sampled?
          assert_equal false, txn_intrinsics["nr.sampled"]
          assert_equal false, err_intrinsics["nr.sampled"]
        end

        def test_transaction_inherits_priority_from_distributed_trace_payload
          payload = create_distributed_trace_payload(sampled: true)

          transaction = in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
          end

          assert_equal transaction.priority, payload.priority
        end

        def test_transaction_doesnt_inherit_priority_from_distributed_trace_payload_when_nil
          payload = create_distributed_trace_payload

          payload.priority = nil

          priority = nil
          transaction = in_transaction "test_txn2" do |txn|
            priority = txn.priority
            txn.accept_distributed_trace_payload payload.to_json
          end

          assert_equal priority, transaction.priority
        end

        def test_transaction_doesnt_inherit_priority_from_distributed_without_sampled_flag
          payload = nil

          in_transaction do |txn|
            payload = txn.create_distributed_trace_payload
          end

          payload.sampled = nil

          priority = nil
          transaction = in_transaction "test_txn2" do |txn|
            priority = txn.priority
            txn.accept_distributed_trace_payload payload.to_json
          end

          assert_equal priority, transaction.priority
        end

        def test_payload_ignored_when_nil
          in_transaction do |txn|
            refute txn.accept_distributed_trace_payload(nil)
          end

          assert_metrics_recorded "Supportability/DistributedTrace/AcceptPayload/Ignored/Null"
        end

        def test_multiple_payload_accepts_ignored
          payload1 = create_distributed_trace_payload.to_json
          payload2 = create_distributed_trace_payload.to_json

          in_transaction do |txn|
            assert txn.accept_distributed_trace_payload(payload1)
            refute txn.accept_distributed_trace_payload(payload2)
          end

          assert_metrics_recorded "Supportability/DistributedTrace/AcceptPayload/Ignored/Multiple"
        end

        def test_payload_rejected_when_accept_is_called_after_create
          payload = create_distributed_trace_payload.to_json

          in_transaction do |txn|
            txn.create_distributed_trace_payload
            refute txn.accept_distributed_trace_payload(payload)
          end

          assert_metrics_recorded "Supportability/DistributedTrace/AcceptPayload/Ignored/CreateBeforeAccept"
        end

        def test_supportability_metric_recorded_when_error_parsing_payload
          payload = "{thisisnotvalidjson"

          in_transaction do |txn|
            refute txn.accept_distributed_trace_payload(payload)
          end

          assert_metrics_recorded "Supportability/DistributedTrace/AcceptPayload/ParseException"
        end

        def test_supportability_metric_recorded_on_major_version_mismatch
          payload = create_distributed_trace_payload

          # we will probably not hit a major version of 1e100
          payload.version = [1e100, 0]

          in_transaction do |txn2|
            refute txn2.accept_distributed_trace_payload(payload.to_json)
          end

          assert_metrics_recorded "Supportability/DistributedTrace/AcceptPayload/Ignored/MajorVersion"
        end

        def test_supportability_metric_recorded_accept_successful
          payload = create_distributed_trace_payload.to_json

          in_transaction do |txn|
            assert txn.accept_distributed_trace_payload(payload)
          end

          assert_metrics_recorded "Supportability/DistributedTrace/AcceptPayload/Success"
        end

        def test_supportability_metric_recorded_on_exception_during_accept
          payload = create_distributed_trace_payload.to_json

          in_transaction do |txn|
            txn.stubs(:check_valid_version).raises(ArgumentError.new("oops!"))
            refute txn.accept_distributed_trace_payload(payload)
          end

          assert_metrics_recorded "Supportability/DistributedTrace/AcceptPayload/Exception"
        end

        def test_supportability_metric_recorded_when_payload_creation_successful
          in_transaction do |txn|
            payload = txn.create_distributed_trace_payload
            refute_nil payload
          end

          assert_metrics_recorded "Supportability/DistributedTrace/CreatePayload/Success"
        end

        def test_supportability_metric_recorded_when_payload_creation_fails
          in_transaction do |txn|
            DistributedTracePayload.stubs(:for_transaction).raises(StandardError.new("oops!"))
            txn.create_distributed_trace_payload
          end

          assert_metrics_recorded "Supportability/DistributedTrace/CreatePayload/Exception"
          refute_metrics_recorded "Supportability/DistributedTrace/CreatePayload/Success"
        end

        private

        def create_distributed_trace_payload(sampled: nil)
          unless sampled.nil?
            NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(sampled)
          end

          in_transaction do |txn|
            return txn.create_distributed_trace_payload
          end
        end

        # Create a chain of transactions which pass distributed
        # tracing information to one another; grandparent calls
        # parent, which in turn calls child.
        #
        def create_distributed_transactions
          result = {}

          result[:grandparent_transaction] = in_transaction "test_txn" do |txn|
            result[:grandparent_payload] =
              txn.create_distributed_trace_payload
          end

          result[:grandparent_intrinsics], _, _ = last_transaction_event

          result[:parent_transaction] = in_transaction "text_txn2" do |txn|
            txn.accept_distributed_trace_payload(
              result[:grandparent_payload].to_json)

            result[:parent_payload] =
              txn.create_distributed_trace_payload
          end

          result[:parent_intrinsics], _, _ = last_transaction_event

          result[:child_transaction] = in_transaction "text_txn3" do |txn|
            txn.accept_distributed_trace_payload(
              result[:parent_payload].to_json)
          end

          result[:child_intrinsics], _, _ = last_transaction_event

          result
        end
      end
    end
  end
end
