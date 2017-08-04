# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_trace_payload'
require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class DistributedTracePayloadTest < Minitest::Test

      def setup
        freeze_time
      end

      def test_payload_is_created_if_connected
        with_config application_id: "46954", cross_process_id: "190#222" do
          created_at = Time.now.to_f
          payload = DistributedTracePayload.new

          assert_equal "46954", payload.caller_app_id
          assert_equal "190", payload.caller_account_id
          assert_equal [2, 0], payload.version
          assert_equal "App", payload.caller_type
          assert_equal created_at, payload.timestamp
        end
      end

      def test_attributes_are_copied_from_transaction
        with_config application_id: "46954", cross_process_id: "190#222" do
          state = NewRelic::Agent::TransactionState.tl_get

          transaction = NewRelic::Agent::Transaction.start state, :controller, :transaction_name => "test_txn"

          payload = DistributedTracePayload.for transaction

          assert_equal transaction.guid, payload.id
        end
      end

      def test_attributes_synthetics_attributes_are_copied_when_present
        with_config application_id: "46954", cross_process_id: "190#222" do
          state = NewRelic::Agent::TransactionState.tl_get

          transaction = NewRelic::Agent::Transaction.start state, :controller, :transaction_name => "test_txn"
          transaction.raw_synthetics_header = "something"
          transaction.synthetics_payload = [1, 1, 100, 200, 300]

          payload = DistributedTracePayload.for transaction

          assert_equal "something", payload.synthetics
          assert_equal 100, payload.synthetics_resource
          assert_equal 200, payload.synthetics_job
          assert_equal 300, payload.synthetics_monitor
        end
      end

      def test_host_copied_from_uri
        with_config application_id: "46954", cross_process_id: "190#222" do
          state = NewRelic::Agent::TransactionState.tl_get
          transaction = NewRelic::Agent::Transaction.start state, :controller, :transaction_name => "test_txn"

          payload = DistributedTracePayload.for transaction, URI("http://newrelic.com")

          assert_equal "newrelic.com", payload.host
        end
      end
    end
  end
end
