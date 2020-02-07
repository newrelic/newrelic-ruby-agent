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
          :trusted_account_key => "190"
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
        carrier = {'HTTP_TRACEPARENT' => 'pretend_this_is_valid'}
        transaction = in_transaction "test_txn" do |txn|
          txn.distributed_tracer.expects(:accept_incoming_request)
          DistributedTracing.accept_distributed_trace_headers carrier, "HTTP"
        end
      end

      def test_accept_distributed_trace_headers_api_with_non_rack
        carrier = {'tRaCePaReNt' => 'pretend_this_is_valid'}
        transaction = in_transaction "test_txn" do |txn|
          txn.distributed_tracer.expects(:accept_trace_context_incoming_request)
          DistributedTracing.accept_distributed_trace_headers carrier, "Kafka"
        end
      end

      def test_insert_distributed_trace_headers_api
        carrier = {}
        transaction = in_transaction "test_txn" do |txn|
          txn.distributed_tracer.expects(:insert_headers)
          DistributedTracing.insert_distributed_trace_headers carrier
        end
      end


      def test_accept_distributed_trace_headers_api_case_insensitive
        carrier = {
          'tRacEpArEnT' => '00-a8e67265afe2773a3c611b94306ee5c2-fb1010463ea28a38-01',
          'trAceSTatE'  => "190@nr=0-0-190-2827902-7d3efb1b173fecfa-e8b91a159289ff74-1-1.23456-1518469636035"
        }
        trace_context_header_data = nil
        transaction = in_transaction "test_txn" do |txn|
          DistributedTracing.accept_distributed_trace_headers carrier, "Kafka"
          trace_context_header_data = txn.distributed_tracer.trace_context_header_data
        end

        trace_parent = trace_context_header_data.trace_parent
  
        assert_equal '00', trace_parent['version']
        assert_equal 'a8e67265afe2773a3c611b94306ee5c2', trace_parent['trace_id']
        assert_equal 'fb1010463ea28a38', trace_parent['parent_id']
        assert_equal '01', trace_parent['trace_flags']
  
        assert_equal '0-0-190-2827902-7d3efb1b173fecfa-e8b91a159289ff74-1-1.23456-1518469636035', trace_context_header_data.trace_state_payload.to_s
      end
    end
  end
end
