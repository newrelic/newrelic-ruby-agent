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

    end
  end
end
