# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_trace_monitor'
require 'net/http'

module NewRelic
  module Agent
    class DistributedTraceMonitorTest < Minitest::Test
      NEWRELIC_TRACE_KEY = 'newrelic'.freeze
      UPCASED_NEWRELIC_TRACE_KEY = 'NEWRELIC'.freeze

      def setup
        @events  = EventListener.new
        @monitor = DistributedTraceMonitor.new(@events)
        @config = {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled' => true,
          :encoding_key                  => "\0",
          :application_id                => "46954",
          :cross_process_id              => "190#46954",
          :trusted_account_key           => "190"
        }

        NewRelic::Agent.config.add_config_for_testing(@config)
        @events.notify(:finished_configuring)
      end

      def teardown
        NewRelic::Agent.config.reset_to_defaults
      end

      def test_accepts_distributed_trace_payload
        payload = nil

        in_transaction "referring_txn" do |txn|
          payload = txn.create_distributed_trace_payload
        end

        env = { NEWRELIC_TRACE_KEY => payload.http_safe }

        in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, env)
          refute_nil txn.distributed_trace_payload
        end
      end
    def test_accepts_distributed_trace_payload_with_differently_cased_newrelic_key
        payload = nil

        in_transaction "referring_txn" do |txn|
          payload = txn.create_distributed_trace_payload
        end

        env = { UPCASED_NEWRELIC_TRACE_KEY => payload.http_safe }

        in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, env)
          refute_nil txn.distributed_trace_payload
        end
      end
    end
  end
end
