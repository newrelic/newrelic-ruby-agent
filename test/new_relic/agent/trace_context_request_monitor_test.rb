# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/trace_context_request_monitor'

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
          :trusted_account_key           => "trust_this!"
        }

        NewRelic::Agent.config.add_config_for_testing(@config)
        @events.notify(:finished_configuring)
      end

      def teardown
        NewRelic::Agent.config.reset_to_defaults
      end
    end
  end
end
