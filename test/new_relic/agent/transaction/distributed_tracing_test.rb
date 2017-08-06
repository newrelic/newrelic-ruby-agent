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
          freeze_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_create_distributed_trace_payload_returns_payload_incrs_order
          with_config application_id: "46954", cross_process_id: "190#222" do
            state = TransactionState.tl_get

            transaction = Transaction.start state, :controller, :transaction_name => "test_txn"
            created_at = Time.now.to_f
            payload = transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
            Transaction.stop(state)

            assert_equal 1, transaction.order
            assert_equal "46954", payload.caller_app_id
            assert_equal "190", payload.caller_account_id
            assert_equal [2, 0], payload.version
            assert_equal "App", payload.caller_type
            assert_equal transaction.guid, payload.id
            assert_equal transaction.distributed_tracing_trip_id, payload.trip_id
            assert_equal transaction.depth, payload.depth
            assert_equal transaction.order, payload.order
            assert_equal "newrelic.com", payload.host
            assert_equal created_at, payload.timestamp

            transaction.create_distributed_trace_payload
            assert_equal 2, transaction.order
          end
        end

        def test_accept_distributed_trace_payload_assigns_payload
          payload = nil

          state = TransactionState.tl_get
          with_config application_id: "46954", cross_process_id: "190#222" do
            transaction = Transaction.start state, :controller, :transaction_name => "test_txn2"
            payload = transaction.create_distributed_trace_payload URI("http://newrelic.com/blog")
            Transaction.stop(state)
          end

          transaction = Transaction.start state, :controller, :transaction_name => "test_txn2"
          transaction.accept_distributed_trace_payload "HTTP", payload.to_json
          Transaction.stop(state)

          refute_nil transaction.inbound_distributed_trace_payload

          assert_equal payload.depth + 1, transaction.depth
          assert_equal payload.trip_id, transaction.distributed_tracing_trip_id
        end
      end
    end
  end
end
