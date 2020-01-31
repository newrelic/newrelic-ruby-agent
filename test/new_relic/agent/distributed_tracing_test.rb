# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_tracing/cross_app_payload'
require 'new_relic/agent/distributed_tracing/distributed_trace_payload'
require 'new_relic/agent/distributed_tracing/distributed_trace_intrinsics'
require 'new_relic/agent/transaction'
require 'net/http'

module NewRelic::Agent
  module DistributedTracing
    class DistributedTracingTest < Minitest::Test
      def setup
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

      def test_create_distributed_trace_payload_api
        in_transaction do |txn|
          txn.distributed_tracer.expects(:create_distributed_trace_payload)
          DistributedTracing.create_distributed_trace_payload
        end
      end

      def test_accept_distributed_trace_payload_api
        in_transaction do |txn|
          txn.distributed_tracer.expects(:create_distributed_trace_payload)
          DistributedTracing.create_distributed_trace_payload
        end
      end

      def test_accept_distributed_trace_headers_api
        carrier = {}
        transaction = in_transaction "test_txn" do |txn|
          txn.distributed_tracer.expects(:accept_incoming_request)
          DistributedTracing.accept_distributed_trace_headers carrier, "HTTP"
        end
      end

      def test_insert_distributed_trace_headers_api
        carrier = {}
        transaction = in_transaction "test_txn" do |txn|
          txn.distributed_tracer.expects(:insert_headers)
          DistributedTracing.insert_distributed_trace_headers carrier
        end
      end

    end
  end
end
