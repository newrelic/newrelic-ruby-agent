# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic::Agent
  module DistributedTracing
    class MonitorTest < Minitest::Test
      def setup
        @events  = EventListener.new
        @monitor = DistributedTracing::Monitor.new(@events)
      end

      def teardown
        Agent.config.reset_to_defaults
      end

      def with_notify_after_config config
        with_config(config) do
          @events.notify(:initial_configuration_complete)
          yield
        end
      end

      def distributed_tracing_enabled
        {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled'      => true,
        }      
      end

      def cat_and_distributed_tracing_enabled
        {
          :'cross_application_tracer.enabled' => true,
          :'distributed_tracing.enabled'      => true,
        }      
      end

      def distributed_tracing_disabled
        {
          :'cross_application_tracer.enabled' => false,
          :'distributed_tracing.enabled'      => false,
        }      
      end

      def test_invokes_accept_incoming_request
        with_notify_after_config distributed_tracing_enabled do
          in_transaction "receiving_txn" do |receiving_txn|
            receiving_txn.distributed_tracer.expects(:accept_incoming_request).at_least_once
            @events.notify(:before_call, {})
          end
        end
      end

      def test_invokes_accept_incoming_request_when_cat_enabled_too
        with_notify_after_config cat_and_distributed_tracing_enabled do
          in_transaction "receiving_txn" do |receiving_txn|
            receiving_txn.distributed_tracer.expects(:accept_incoming_request).at_least_once
            @events.notify(:before_call, {})
          end
        end
      end

      def test_skips_accept_incoming_request
        with_notify_after_config distributed_tracing_disabled do
          in_transaction "receiving_txn" do |receiving_txn|
            receiving_txn.distributed_tracer.expects(:accept_incoming_request).never
            @events.notify(:before_call, {})
          end
        end
      end

    end
  end
end
