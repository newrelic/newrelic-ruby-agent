# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/opentelemetry_bridge'

module NewRelic
  module Agent
    class OpenTelemetryBridgeTest < Minitest::Test
      class BridgeInstallationError < StandardError; end

      def setup
        @config = {
          :'opentelemetry.enabled' => true,
          :'opentelemetry.traces.enabled' => true
        }
        NewRelic::Agent.config.add_config_for_testing(@config)
      end

      def teardown
        NewRelic::Agent.config.reset_to_defaults
      end

      def test_does_not_run_requires_without_opentelemetry_api_gem
        assert NewRelic::Agent::OpenTelemetryBridge.new
      end

      def test_does_not_run_requires_without_config
        with_config(:'opentelemetry.enabled' => false) do
          Object.stub_const(:OpenTelemetry, nil) do
            assert NewRelic::Agent::OpenTelemetryBridge.new
          end
        end
      end

      def test_installs_bridge_when_configured
        Object.stub_const(:OpenTelemetry, nil) do
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
            assert_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new }
          end
        end
      end

      def test_adds_supportability_metric_when_opentelemetry_enabled
        Object.stub_const(:OpenTelemetry, true) do
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { nil }) do
            NewRelic::Agent::OpenTelemetryBridge.new

            assert_metrics_recorded('Supportability/Tracing/Ruby/OpenTelemetryBridge/enabled')
          end
        end
      end

      def test_adds_supportability_metric_when_opentelemetry_disabled
        with_config(:'opentelemetry.enabled' => false) do
          NewRelic::Agent::OpenTelemetryBridge.new

          assert_metrics_recorded('Supportability/Tracing/Ruby/OpenTelemetryBridge/disabled')
        end
      end
    end
  end
end
