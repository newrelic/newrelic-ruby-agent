# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/trace_context_request_monitor'
require 'new_relic/agent/trace_context'

module NewRelic
  module Agent
    class TraceContextRequestMonitorTest < Minitest::Test
      def setup
        @events  = EventListener.new
        @monitor = TraceContextRequestMonitor.new(@events)
        @config = {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled' => false,
          :'trace_context.enabled'       => true,
          :encoding_key                  => "\0",
          :account_id                    => "190",
          :primary_application_id        => "46954",
          :trusted_account_key           => "99999"
        }

        NewRelic::Agent.config.add_config_for_testing(@config)
        NewRelic::Agent::Transaction.any_instance.stubs(:connected?).returns(true)
        @events.notify(:finished_configuring)
      end

      def teardown
        NewRelic::Agent.config.reset_to_defaults
      end

      def test_accepts_trace_context
        parent_txn, carrier = build_parent_transaction_headers

        child_txn = in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, carrier)
        end

        refute_nil child_txn.trace_context_data
        assert_equal parent_txn.guid, child_txn.parent_transaction_id
        assert_equal parent_txn.trace_id, child_txn.trace_id
      end

      def test_accepts_trace_context_with_trace_parent_and_no_trace_state
        carrier = {'HTTP_TRACEPARENT' => '00-12345678901234567890123456789012-1234567890123456-01'}
        txn = in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, carrier)
        end

        assert_equal '12345678901234567890123456789012', txn.trace_id
      end

      def test_accepts_trace_context_with_empty_trace_state
        carrier = {
          'HTTP_TRACEPARENT' => '00-12345678901234567890123456789012-1234567890123456-00',
          'HTTP_TRACESTATE' => ''
        }
        txn = in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, carrier)
        end

        assert_equal '12345678901234567890123456789012', txn.trace_id
      end

      def test_restarts_trace_on_all_zero_trace_id
        carrier = {
          'HTTP_TRACEPARENT' => '00-00000000000000000000000000000000-1234567890123456-00',
          'HTTP_TRACESTATE' => ''
        }
        txn = in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, carrier)
        end

        refute_equal '00000000000000000000000000000000', txn.trace_id
      end

      def test_does_not_accept_trace_context_if_trace_context_disabled
        with_config @config.merge({ :'trace_context.enabled' => false }) do
          _, carrier = build_parent_transaction_headers

          child_txn = in_transaction "receiving_txn" do |txn|
            @events.notify(:before_call, carrier)
          end
          assert_nil child_txn.trace_context_data
        end
      end

      def test_does_not_accept_trace_context_if_not_in_transaction
        _, carrier = build_parent_transaction_headers
        assert_nil @monitor.on_before_call(carrier)
      end

      def test_does_not_accept_trace_context_if_no_trace_context_headers
        carrier = {}
        child_txn = in_transaction 'child' do |txn|
          @events.notify(:before_call, carrier)
        end

        assert_nil child_txn.trace_context_data
      end

      def test_does_not_accept_malformed_trace_context
        carrier ={
          'HTTP_TRACESTATE' => 'alsdkfja;lskdjfa',
          'HTTP_TRACEPARENT' => 'alkjhdsfasdf'
        }

        child_txn = in_transaction 'child' do |txn|
          @events.notify(:before_call, carrier)
        end

        assert_nil child_txn.trace_context_data
      end

      def build_parent_transaction_headers
        carrier = {}

        parent_txn = in_transaction "referring_txn" do |txn|
          txn.sampled = true
          txn.insert_trace_context format: TraceContext::FORMAT_RACK,
                                   carrier: carrier
        end
        [parent_txn, carrier]
      end
    end
  end
end
