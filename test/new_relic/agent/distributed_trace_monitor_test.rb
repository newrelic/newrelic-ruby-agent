# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_trace_monitor'
require 'net/http'

module NewRelic
  module Agent
    class DistributedTraceMonitorTest < Minitest::Test
      NEWRELIC_TRACE_KEY = 'HTTP_NEWRELIC'.freeze

      def setup
        @events  = EventListener.new
        @monitor = DistributedTraceMonitor.new(@events)
        @config = {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled' => true,
          :encoding_key                  => "\0",
          :account_id                    => "190",
          :primary_application_id        => "46954",
          :trusted_account_key           => "trust_this!"
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

      def test_sets_transport_type_for_http_scheme
        payload = nil

        in_transaction "referring_txn" do |txn|
          payload = txn.create_distributed_trace_payload
        end

        env = {
          NEWRELIC_TRACE_KEY => payload.http_safe,
          'rack.url_scheme'  => 'http'
        }

        in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, env)
          payload = txn.distributed_trace_payload
        end

        assert_equal 'HTTP', payload.caller_transport_type
      end

      def test_sets_transport_type_for_https_scheme
        payload = nil

        in_transaction "referring_txn" do |txn|
          payload = txn.create_distributed_trace_payload
        end

        env = {
          NEWRELIC_TRACE_KEY => payload.http_safe,
          'rack.url_scheme'  => 'https'
        }

        in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, env)
          payload = txn.distributed_trace_payload
        end

        assert_equal 'HTTPS', payload.caller_transport_type
      end
    end
  end
end
