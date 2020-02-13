# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic::Agent
  module DistributedTracing
    class DistributedTraceMonitorTest < Minitest::Test
      NEWRELIC_TRACE_KEY = 'HTTP_NEWRELIC'.freeze

      def setup
        Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)

        @events  = EventListener.new
        @monitor = DistributedTracing::Monitor.new(@events)
        @config = {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled' => true,
          :encoding_key                  => "\0",
          :account_id                    => "190",
          :primary_application_id        => "46954",
          :trusted_account_key           => "trust_this!"
        }
        DistributedTracePayload.stubs(:connected?).returns(true)

        Agent.config.add_config_for_testing(@config)
        @events.notify(:initial_configuration_complete)
      end

      def teardown
        Agent.config.reset_to_defaults
      end

      def after_notify_event rack_scheme=nil
        payload = nil

        in_transaction "referring_txn" do |txn|
          payload = txn.distributed_tracer.create_distributed_trace_payload
        end

        env = { NEWRELIC_TRACE_KEY => payload.http_safe }
        env['rack.url_scheme'] = rack_scheme if rack_scheme

        in_transaction "receiving_txn" do |txn|
          @events.notify(:before_call, env)
          yield txn
        end
      end

      def test_accepts_distributed_trace_payload
        after_notify_event do |txn|
          refute_nil txn.distributed_tracer.distributed_trace_payload
        end
      end

      def test_sets_transport_type_for_http_scheme
        after_notify_event 'http' do |txn|
          assert_equal 'HTTP', txn.distributed_tracer.caller_transport_type
        end
      end

      def test_sets_transport_type_for_https_scheme
        after_notify_event 'https' do |txn|
          assert_equal 'HTTPS', txn.distributed_tracer.caller_transport_type
        end
      end
    end
  end
end
