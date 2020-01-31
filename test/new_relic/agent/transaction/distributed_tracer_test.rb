# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

require 'new_relic/agent/messaging'
require 'new_relic/agent/transaction'

module NewRelic::Agent
  module DistributedTracing
    class DistributedTracerTest < Minitest::Test

      def teardown
        NewRelic::Agent::Transaction::TraceContext::AccountHelpers.instance_variable_set :@trace_state_entry_key, nil
        NewRelic::Agent.drop_buffered_data
      end

      def distributed_tracing_enabled
        {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled'      => true,
          :account_id => "190",
          :primary_application_id => "46954",
          :trusted_account_key => "trust_this!"
        }
      end

      def exclude_newrelic_header_setting value
        distributed_tracing_enabled.merge :'exclude_newrelic_header' => value
      end

      def build_trace_context_header env={}
        env['HTTP_TRACEPARENT'] = '00-12345678901234567890123456789012-1234567890123456-00'
        env['HTTP_TRACESTATE'] = ''
        return env
      end

      def build_distributed_trace_header env={}
        begin
          NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
          with_config distributed_tracing_enabled do
            in_transaction "referring_txn" do |txn|
              payload = txn.distributed_tracer.create_distributed_trace_payload
              assert payload, "failed to build a distributed_trace payload!"
              env['HTTP_NEWRELIC'] = payload.http_safe
            end
          end
          return env
        ensure
          NewRelic::Agent::DistributedTracePayload.unstub(:connected?)
        end
      end

      def tests_accepts_trace_context_header
        env = build_trace_context_header
        refute env['HTTP_NEWRELIC']
        assert env['HTTP_TRACEPARENT']

        with_config(distributed_tracing_enabled) do
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            assert txn.distributed_tracer.trace_context_header_data, "Expected to accept trace context headers"
            refute txn.distributed_tracer.distributed_trace_payload, "Did not expect to accept a distributed trace payload"
          end
        end
      end

      def tests_accepts_distributed_trace_header
        env = build_distributed_trace_header
        assert env['HTTP_NEWRELIC']
        refute env['HTTP_TRACEPARENT']

        with_config(distributed_tracing_enabled) do
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            refute txn.distributed_tracer.trace_context_header_data, "Did not expect to accept trace context headers"
            assert txn.distributed_tracer.distributed_trace_payload, "Expected to accept a distributed trace payload"
          end
        end
      end

      def tests_ignores_distributed_trace_header_when_context_trace_header_present
        env = build_distributed_trace_header build_trace_context_header
        assert env['HTTP_NEWRELIC']
        assert env['HTTP_TRACEPARENT']

        with_config(distributed_tracing_enabled) do
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            assert txn.distributed_tracer.trace_context_header_data, "Expected to accept trace context headers"
            refute txn.distributed_tracer.distributed_trace_payload, "Did not expect to accept a distributed trace payload"
          end
        end
      end

      def tests_does_not_crash_when_no_distributed_trace_headers_are_present
        in_transaction do |txn|
          txn.distributed_tracer.accept_incoming_request({})
          assert_nil txn.distributed_tracer.trace_context_header_data
          assert_nil txn.distributed_tracer.distributed_trace_payload
        end
      end

      def tests_outbound_distributed_trace_headers_present_when_exclude_is_false
        env = build_distributed_trace_header build_trace_context_header
        assert env['HTTP_NEWRELIC']
        assert env['HTTP_TRACEPARENT']

        with_config exclude_newrelic_header_setting(true) do
          NewRelic::Agent.instance.stubs(:connected?).returns(true)
          request = {}
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            txn.distributed_tracer.insert_headers request
            assert request['traceparent'], "expected traceparent header to be present in #{request.keys}"
            assert request['tracestate'], "expected tracestate header to be present #{request.keys}"
            refute request['newrelic'], "expected distributed trace header to NOT be present in #{request.keys}"
          end
        end
      end

      def tests_outbound_distributed_trace_headers_omitted_when_exclude_is_true
        env = build_distributed_trace_header build_trace_context_header
        assert env['HTTP_NEWRELIC']
        assert env['HTTP_TRACEPARENT']

        with_config exclude_newrelic_header_setting(false) do
          NewRelic::Agent.instance.stubs(:connected?).returns(true)
          request = {}
          in_transaction do |txn|
            txn.distributed_tracer.accept_incoming_request env
            txn.distributed_tracer.insert_headers request
            assert request['traceparent'], "expected traceparent header to be present in #{request.keys}"
            assert request['tracestate'], "expected tracestate header to be present #{request.keys}"
            assert request['newrelic'], "expected distributed trace header to be present in #{request.keys}"
          end
        end
      end
    end
  end
end
