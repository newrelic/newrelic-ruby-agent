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

        def test_create_distributed_trace_payload_returns_payload
          nr_freeze_time
          created_at = (Time.now.to_f * 1000).round
          state = TransactionState.tl_get

          transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
          payload = transaction.create_distributed_trace_payload
          Transaction.stop(state)

          assert_equal "46954", payload.parent_app_id
          assert_equal "190", payload.parent_account_id
          assert_equal "trust_this!", payload.trusted_account_key
          assert_equal DistributedTracePayload::VERSION, payload.version
          assert_equal "App", payload.parent_type
          assert_equal transaction.initial_segment.guid, payload.id
          assert_equal transaction.guid, payload.transaction_id
          assert_equal transaction.trace_id, payload.trace_id
          assert_equal created_at, payload.timestamp
        end

        def test_create_distributed_trace_payload_while_disconnected_returns_nil
          nr_freeze_time
          state = TransactionState.tl_get

          payload = 'definitely not nil'
          with_config(account_id: nil, primary_application_id: nil) do
            transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
            payload = transaction.create_distributed_trace_payload
            Transaction.stop(state)
          end

          assert_nil payload
        end

        def test_accept_distributed_trace_payload_assigns_json_payload
          payload = create_distributed_trace_payload

          transaction = in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
          end

          refute_nil transaction.distributed_trace_payload

          assert_equal transaction.trace_id, payload.trace_id
        end

        def test_accept_distributed_trace_payload_assigns_http_safe_payload
          payload = create_distributed_trace_payload

          transaction = in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.http_safe
          end

          refute_nil transaction.distributed_trace_payload

          assert_equal transaction.trace_id, payload.trace_id
        end

        def test_accept_distributed_trace_payload_rejects_untrusted_account_with_trusted_account_id
          payload = create_distributed_trace_payload

          transaction = nil
          accepted    = nil

          with_config(trusted_account_key: "somekey") do
            transaction = in_transaction "test_txn" do |txn|
              accepted = txn.accept_distributed_trace_payload payload.http_safe
            end
          end

          assert_nil              transaction.distributed_trace_payload
          assert_false            accepted
          assert_metrics_recorded ['Supportability/DistributedTrace/AcceptPayload/Ignored/UntrustedAccount']
        end

        def test_accept_distributed_trace_payload_rejects_untrusted_account_without_trusted_account_id
          # without a trusted account key in the payload the agent will compare against the parent_app_id
          payload = create_distributed_trace_payload
          payload.trusted_account_key = nil

          transaction = nil
          accepted    = nil

          with_config(trusted_account_key: "somekey") do
            transaction = in_transaction "test_txn" do |txn|
              accepted = txn.accept_distributed_trace_payload payload.http_safe
            end
          end

          assert_nil              transaction.distributed_trace_payload
          assert_false            accepted
          assert_metrics_recorded ['Supportability/DistributedTrace/AcceptPayload/Ignored/UntrustedAccount']
        end

        def test_accept_distributed_trace_payload_accepts_payload_when_account_id_matches_trusted_key
          payload = create_distributed_trace_payload
          payload.trusted_account_key = nil
          payload.parent_account_id = "matching_key"

          transaction = nil
          accepted    = nil

          with_config(trusted_account_key: "matching_key") do
            transaction = in_transaction "test_txn" do |txn|
              accepted = txn.accept_distributed_trace_payload payload.http_safe
            end
          end

          assert accepted
          refute_nil transaction.distributed_trace_payload
        end

        def test_accept_distributed_trace_payload_accepts_payload_when_account_id_matches_trusted_key
          payload = create_distributed_trace_payload
          payload.trusted_account_key = nil
          payload.parent_account_id = "500"

          transaction = nil
          accepted    = nil

          with_config(trusted_account_key: "500") do
            transaction = in_transaction "test_txn" do |txn|
              accepted = txn.accept_distributed_trace_payload payload.http_safe
            end
          end

          assert accepted
          refute_nil transaction.distributed_trace_payload
        end

        def test_accept_distributed_trace_payload_records_duration_metrics
          payload = create_distributed_trace_payload

          in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
          end

          assert_metrics_recorded ['DurationByCaller/App/190/46954/Unknown/all',
                                   'DurationByCaller/App/190/46954/Unknown/allOther']

          assert_metrics_recorded ['TransportDuration/App/190/46954/Unknown/all',
                                   'TransportDuration/App/190/46954/Unknown/allOther']

          refute_metrics_recorded ['ErrorsByCaller/App/190/46954/Unknown/all',
                                   'ErrorsByCaller/App/190/46954/Unknown/allOther']

        end

        def test_accept_distributed_trace_payload_with_error_records_error_metrics
          payload = create_distributed_trace_payload

          in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
            NewRelic::Agent.notice_error StandardError.new "Nooo!"
          end

          assert_metrics_recorded ['ErrorsByCaller/App/190/46954/Unknown/all',
                                   'ErrorsByCaller/App/190/46954/Unknown/allOther']

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
          intrinsics  = result[:grandparent_intrinsics]

          assert_equal transaction.guid, intrinsics['guid']
          assert_equal transaction.guid, intrinsics['traceId']
          assert_nil                     intrinsics['parentId']
          assert                         intrinsics['sampled']

          txn_intrinsics = transaction.attributes.intrinsic_attributes_for AttributeFilter::DST_TRANSACTION_TRACER

          assert_equal transaction.guid, txn_intrinsics['guid']
          assert_equal transaction.guid, intrinsics['traceId']
          assert_nil                     txn_intrinsics['parentId']
          assert                         txn_intrinsics['sampled']
        end

        def test_initial_legacy_cat_request_trace_id_overwritten_by_first_distributed_trace_guid
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
          assert_equal transaction.guid, intrinsics['traceId']

          txn_intrinsics = transaction.attributes.intrinsic_attributes_for AttributeFilter::DST_TRANSACTION_TRACER
          assert_equal transaction.guid, intrinsics['traceId']
        end

        def test_intrinsics_assigned_to_transaction_event_from_distributed_trace
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          result                  = create_distributed_transactions
          parent_transaction      = result[:parent_transaction]
          child_transaction       = result[:child_transaction]
          child_intrinsics        = result[:child_intrinsics]

          inbound_payload = child_transaction.distributed_trace_payload

          assert_equal inbound_payload.parent_type,           child_intrinsics["parent.type"]
          assert_equal inbound_payload.caller_transport_type, child_intrinsics["parent.transportType"]
          assert_equal inbound_payload.parent_app_id,         child_intrinsics["parent.app"]
          assert_equal inbound_payload.parent_account_id,     child_intrinsics["parent.account"]

          assert_equal inbound_payload.trace_id,              child_intrinsics["traceId"]
          assert_equal inbound_payload.id,                    child_intrinsics["parentSpanId"]
          assert_equal child_transaction.guid,                child_intrinsics["guid"]
          assert_equal true,                                  child_intrinsics["sampled"]

          assert                                              child_intrinsics["parentId"]
          assert_equal parent_transaction.guid,               child_intrinsics["parentId"]

          # Make sure the parent / grandparent links are connected all
          # the way up.
          #
          assert_equal inbound_payload.transaction_id,        parent_transaction.guid
        end

        def test_sampled_is_false_in_transaction_event_when_indicated_by_upstream
          payload = create_distributed_trace_payload(sampled: false)

          in_transaction "test_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
          end

          intrinsics, _, _ = last_transaction_event
          assert_equal false, intrinsics["sampled"]
        end

        def test_agent_attributes_always_recorded_when_distributed_tracing_enabled

          in_transaction("test_txn") {}

          intrinsics, _, _ = last_transaction_event

          assert intrinsics.key?('traceId')
          assert intrinsics.key?('guid')
          assert intrinsics.key?('priority')
          assert intrinsics.key?('sampled')
        end

        def test_intrinsics_assigned_to_error_event_from_distributed_trace
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
          assert_equal inbound_payload.caller_transport_type, intrinsics["parent.transportType"]
          assert_equal inbound_payload.parent_app_id, intrinsics["parent.app"]
          assert_equal inbound_payload.parent_account_id, intrinsics["parent.account"]
          assert_equal inbound_payload.transaction_id, referring_transaction.guid
          assert_equal transaction.guid, intrinsics["guid"]
          assert_equal inbound_payload.trace_id, intrinsics["traceId"]
          assert_equal true, intrinsics["sampled"]
          assert       intrinsics["parentId"], "Child should be linked to parent transaction"
          assert_equal inbound_payload.transaction_id, intrinsics["parentId"]
        end

        def test_sampled_is_false_in_error_event_when_indicated_by_upstream
          payload = create_distributed_trace_payload(sampled: false)

          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          in_transaction "text_txn" do |txn|
            txn.accept_distributed_trace_payload payload.to_json
            NewRelic::Agent.notice_error StandardError.new "Nooo!"
          end

          intrinsics, _, _ = last_error_event
          assert_equal false, intrinsics["sampled"]
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
          assert_equal true, intrinsics["sampled"]
        end

        def test_sampled_flag_added_to_intrinsics_without_distributed_trace_when_true
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          transaction = in_transaction("test_txn") do
            NewRelic::Agent.notice_error StandardError.new("Sorry!")
          end

          txn_intrinsics, _, _ = last_transaction_event
          err_intrinsics, _, _ = last_error_event

          assert_equal true, transaction.sampled?
          assert_equal true, txn_intrinsics["sampled"]
          assert_equal true, err_intrinsics["sampled"]
        end

        def test_sampled_flag_added_to_intrinsics_without_distributed_trace_when_false
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(false)

          transaction = in_transaction("test_txn") do
            NewRelic::Agent.notice_error StandardError.new("Sorry!")
          end

          txn_intrinsics, _, _ = last_transaction_event
          err_intrinsics, _, _ = last_error_event

          assert_equal false, transaction.sampled?
          assert_equal false, txn_intrinsics["sampled"]
          assert_equal false, err_intrinsics["sampled"]
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

        def test_sampled_and_priority_inherited_when_accepting_distributed_trace_payload
          payload = create_distributed_trace_payload(sampled: true)

          in_transaction('test_txn') do |txn|
            txn.accept_distributed_trace_payload(payload.to_json)

            assert_equal true, txn.sampled?
            assert_equal payload.priority, txn.priority
          end
        end

        def test_sampling_decisions_only_made_for_transactions_without_payloads
          payload = create_distributed_trace_payload(sampled: true)
          # this is a little ugly, but the code below forces the adaptive
          # sampler into a new interval and resets the counts
          adaptive_sampler = NewRelic::Agent.instance.adaptive_sampler
          interval_duration = adaptive_sampler.instance_variable_get :@period_duration
          nr_freeze_time
          advance_time(interval_duration)
          adaptive_sampler.send(:reset_if_period_expired!)

          20.times do
            in_transaction('test_txn') do |txn|
              txn.accept_distributed_trace_payload payload.to_json
            end
          end
          assert_equal 0, adaptive_sampler.stats[:seen]

          20.times do
            in_transaction {}
          end
          assert_equal 20, adaptive_sampler.stats[:seen]
        end

        private

        def create_distributed_trace_payload(sampled: nil)
          in_transaction do |txn|
            payload = txn.create_distributed_trace_payload
            payload.sampled = sampled
            return payload
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
